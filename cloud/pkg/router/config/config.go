package config

import (
	"encoding/pem"
	"io/ioutil"
	"k8s.io/klog/v2"
	"sync"

	"github.com/kubeedge/kubeedge/pkg/apis/componentconfig/cloudcore/v1alpha1"
)

var Config Configure
var once sync.Once

type Configure struct {
	v1alpha1.Router
	Ca   []byte
	Cert []byte
	Key  []byte
}

func InitConfigure(router *v1alpha1.Router) {
	once.Do(func() {
		Config = Configure{
			Router: *router,
		}

		if !router.IsSecure {
			return
		}

		ca, err := ioutil.ReadFile(router.TLSRouterCAFile)
		if err == nil {
			block, _ := pem.Decode(ca)
			ca = block.Bytes
		}
		if ca != nil {
			Config.Ca = ca
		}

		cert, err := ioutil.ReadFile(router.TLSRouterCertFile)
		if err == nil {
			block, _ := pem.Decode(cert)
			cert = block.Bytes
		}

		key, err := ioutil.ReadFile(router.TLSRouterPrivateKeyFile)
		if err == nil {
			block, _ := pem.Decode(key)
			key = block.Bytes
		}

		if cert != nil && key != nil {
			Config.Cert = cert
			Config.Key = key
		} else if !(cert == nil && key == nil) {
			klog.Fatal("Both of routerCert and key should be specified!")
		}
	})
}
