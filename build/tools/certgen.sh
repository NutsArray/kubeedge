#!/usr/bin/env bash

set -o errexit

readonly caPath=${CA_PATH:-/etc/kubeedge/ca}
readonly caSubject=${CA_SUBJECT:-/C=CN/ST=Zhejiang/L=Hangzhou/O=KubeEdge/CN=kubeedge.io}
readonly certPath=${CERT_PATH:-/etc/kubeedge/certs}
readonly subject=${SUBJECT:-/C=CN/ST=Zhejiang/L=Hangzhou/O=KubeEdge/CN=kubeedge.io}

genCA() {
    openssl genrsa -des3 -out ${caPath}/rootCA.key -passout pass:kubeedge.io 4096
    openssl req -x509 -new -nodes -key ${caPath}/rootCA.key -sha256 -days 3650 \
    -subj ${subject} -passin pass:kubeedge.io -out ${caPath}/rootCA.crt
}

ensureCA() {
    if [ ! -e ${caPath}/rootCA.key ] || [ ! -e ${caPath}/rootCA.crt ]; then
        genCA
    fi
}

ensureFolder() {
    if [ ! -d ${caPath} ]; then
        mkdir -p ${caPath}
    fi
    if [ ! -d ${certPath} ]; then
        mkdir -p ${certPath}
    fi
}

genCsr() {
    local name=$1
    openssl genrsa -out ${certPath}/${name}.key 2048
    openssl req -new -key ${certPath}/${name}.key -subj ${subject} -out ${certPath}/${name}.csr
}

genCert() {
    local name=$1
    openssl x509 -req -in ${certPath}/${name}.csr -CA ${caPath}/rootCA.crt -CAkey ${caPath}/rootCA.key \
    -CAcreateserial -passin pass:kubeedge.io -out ${certPath}/${name}.crt -days 365 -sha256
}

genCertAndKey() {
    ensureFolder
    ensureCA
    local name=$1
    genCsr $name
    genCert $name
}

GenSpecificCaAndCert() {
    readonly specificsubject=${SUBJECT:-/C=CN/ST=Zhejiang/L=Hangzhou/O=KubeEdge}
    if [ ! -n "$1" ];then
        echo -e "You must set Output CA and Cert Files Name"
        exit 1
    fi

    if [ -n "$2" ];then
        ROOT_CA_FILE=$2
    else
        ROOT_CA_FILE=/etc/kubernetes/pki/ca.crt
        echo -e "Root CA's path and name are not set, use default: "$ROOT_CA_FILE
    fi

    if [ -n "$3" ];then
        ROOT_CA_KEY_FILE=$3
    else
        ROOT_CA_KEY_FILE=/etc/kubernetes/pki/ca.key
        echo -e "Root Key's path and name are not set, use default: "$ROOT_CA_KEY_FILE
    fi

    if [ -n "$4" ];then
        CA_FILE=$4/$1"CA.crt"
    else
        CA_FILE=${caPath}/$1"CA.crt"
        echo -e "Output ca Path and Name are not set,use Default: "$CA_FILE
    fi

    if [ -n "$5" ];then
        KEY_FILE=$4/$1".key"
        CSR_FILE=$4/$1".csr"
        CRT_FILE=$4/$1".crt"
    else
        KEY_FILE=${certPath}/$1".key"
        CSR_FILE=${certPath}/$1".csr"
        CRT_FILE=${certPath}/$1".crt"
        echo -e "Output certs Path and Name are not set,use Default: "$KEY_FILE","$CSR_FILE","$CRT_FILE
    fi


    if [ -z ${CLOUDCOREIPS} ]; then
        echo "You must set CLOUDCOREIPS Env,The environment variable is set to specify the IP addresses of all cloudcore"
        echo "If there are more than one IP need to be separated with space."
        exit 1
    fi

    echo "Output CAFile: $CA_FILE"
    echo "Output CertFile: $CRT_FILE"
    echo "Output PrivateKeyFile: $KEY_FILE"

    index=1
    SUBJECTALTNAME="subjectAltName = IP.1:127.0.0.1"
    for ip in ${CLOUDCOREIPS}; do
        SUBJECTALTNAME="${SUBJECTALTNAME},"
        index=$(($index+1))
        SUBJECTALTNAME="${SUBJECTALTNAME}IP.${index}:${ip}"
    done

    cp $ROOT_CA_FILE $CA_FILE
    echo $SUBJECTALTNAME > /tmp/server-extfile.cnf

    openssl genrsa -out ${KEY_FILE}  2048
    openssl req -new -key ${KEY_FILE} -subj ${specificsubject} -out ${CSR_FILE}

    # verify
    openssl req -in ${CSR_FILE} -noout -text
    openssl x509 -req -in ${CSR_FILE} -CA ${ROOT_CA_FILE} -CAkey ${ROOT_CA_KEY_FILE} -CAcreateserial -out ${CRT_FILE} -days 5000 -sha256 -extfile /tmp/server-extfile.cnf
    #verify
    openssl x509 -in ${CRT_FILE} -text -noout
}

stream() {
    ensureFolder
    readonly streamsubject=${SUBJECT:-/C=CN/ST=Zhejiang/L=Hangzhou/O=KubeEdge}
    readonly STREAM_KEY_FILE=${certPath}/stream.key
    readonly STREAM_CSR_FILE=${certPath}/stream.csr
    readonly STREAM_CRT_FILE=${certPath}/stream.crt
    readonly K8SCA_FILE=/etc/kubernetes/pki/ca.crt
    readonly K8SCA_KEY_FILE=/etc/kubernetes/pki/ca.key

    if [ -z ${CLOUDCOREIPS} ]; then
        echo "You must set CLOUDCOREIPS Env,The environment variable is set to specify the IP addresses of all cloudcore"
        echo "If there are more than one IP need to be separated with space."
        exit 1
    fi

    index=1
    SUBJECTALTNAME="subjectAltName = IP.1:127.0.0.1"
    for ip in ${CLOUDCOREIPS}; do
        SUBJECTALTNAME="${SUBJECTALTNAME},"
        index=$(($index+1))
        SUBJECTALTNAME="${SUBJECTALTNAME}IP.${index}:${ip}"
    done

    cp /etc/kubernetes/pki/ca.crt ${caPath}/streamCA.crt
    echo $SUBJECTALTNAME > /tmp/server-extfile.cnf

    openssl genrsa -out ${STREAM_KEY_FILE}  2048
    openssl req -new -key ${STREAM_KEY_FILE} -subj ${streamsubject} -out ${STREAM_CSR_FILE}

    # verify
    openssl req -in ${STREAM_CSR_FILE} -noout -text
    openssl x509 -req -in ${STREAM_CSR_FILE} -CA ${K8SCA_FILE} -CAkey ${K8SCA_KEY_FILE} -CAcreateserial -out ${STREAM_CRT_FILE} -days 5000 -sha256 -extfile /tmp/server-extfile.cnf
    #verify
    openssl x509 -in ${STREAM_CRT_FILE} -text -noout
}

buildSecret() {
    local name="edge"
    genCertAndKey ${name} > /dev/null 2>&1
    cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudcore
  namespace: kubeedge
  labels:
    k8s-app: kubeedge
    kubeedge: cloudcore
stringData:
  rootCA.crt: |
$(pr -T -o 4 ${caPath}/rootCA.crt)
  edge.crt: |
$(pr -T -o 4 ${certPath}/${name}.crt)
  edge.key: |
$(pr -T -o 4 ${certPath}/${name}.key)

EOF
}

$1 "$2" "$3" "$4" "$5" "$6"
