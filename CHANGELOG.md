### 0.13.0
*Features*
- Added support for StatefulSets for kubernetes 1.7+ using RollingUpdate

*Bug Fixes*
- Explicitly require the minimum rest-client version required by kubeclient ([#202](https://github.com/Shopify/kubernetes-deploy/pull/202))

*Enhancements*
- Begin official support for Kubernetes v1.8 ([#198](https://github.com/Shopify/kubernetes-deploy/pull/198), [#200](https://github.com/Shopify/kubernetes-deploy/pull/200))

### 0.12.12
*Bug Fixes*
- Fix an issue deploying Shopify's internal custom resources.

### 0.12.11
*Bug Fixes*
- Stop appending newlines to the base64-encoded values of secrets created from ejson. These extra newlines were preventing the ejson->k8s secret feature from working with v1.8 (https://github.com/Shopify/kubernetes-deploy/pull/196).

### 0.12.10
*Enhancement*
- Log reason if deploy times out due to `progressDeadlineSeconds` being exceeded

### 0.12.9
*Bug Fixes*
- Retry discovering namespace and kubernetes context
- Expose real error during namespace discovery

### 0.12.8
*Bug Fixes*
- Force deployment to use its own hard timeout instead of relying on the replica set
