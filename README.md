~~~
[root@ushift06 ~]# oc get ns|egrep "demo-app|spring"
demo-app                             Active   84d
spring-petclinic                     Active   78d
[root@ushift06 ~]# 
~~~

demo-app => where is placed the application that needs to read the secret resource
spring-petclinic => where the secrets is placed on. 

1. Create the ServiceAccount (if it doesn't exist):

~~~
[root@ushift06 tmp]# cat serviceaccount.yaml 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-serviceaccount
  namespace: demo-app

[root@ushift06 tmp]# oc create -f serviceaccount.yaml 
serviceaccount/my-serviceaccount created
[root@ushift06 tmp]# 
~~~

2. Define a Role and a ClusterRole binding (in the target namespace) that grants "view" access to secrets:

~~~
[root@ushift06 tmp]# cat role-targetns.yaml 
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-viewer
  namespace: spring-petclinic
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
[root@ushift06 tmp]# oc create -f role-targetns.yaml 
role.rbac.authorization.k8s.io/secret-viewer created
[root@ushift06 tmp]# cat cluster-rolebinding.yaml 
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-serviceaccount-secret-viewer-binding
  namespace: spring-petclinic # The RoleBinding lives in the target namespace
subjects:
- kind: ServiceAccount
  name: my-serviceaccount
  namespace: demo-app # Specify the namespace where the ServiceAccount exists
roleRef:
  kind: Role
  name: secret-viewer # Reference the Role created in step 2
  apiGroup: rbac.authorization.k8s.io
[root@ushift06 tmp]# oc create -f cluster-rolebinding.yaml 
rolebinding.rbac.authorization.k8s.io/my-serviceaccount-secret-viewer-binding created
[root@ushift06 tmp]# 
~~~

3. Test it 

~~~
[root@ushift06 tmp]# cat secret.yaml 
# data-namespace-test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-test-secret
  namespace: spring-petclinic
type: Opaque
stringData:
  testkey: "testvalue"
[root@ushift06 tmp]# oc create -f secret.yaml 
secret/my-test-secret created
[root@ushift06 tmp]# 


[root@ushift06 tmp]# cat pod-test.yaml 
# app-namespace-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-viewer-test-pod
  namespace: demo-app # Pod runs in app-namespace
spec:
  serviceAccountName: my-serviceaccount # Use the service account with permissions
  # --- START of the crucial securityContext block for the Pod ---
  securityContext:
    runAsNonRoot: true # Enforce running as a non-root user
    seccompProfile:
      type: RuntimeDefault # Use the default seccomp profile
  # --- END of the crucial securityContext block for the Pod ---
  containers:
  - name: test-secret-access
    image: quay.io/rhn_support_arolivei/sample-app-minimal:latest
    command: ["/bin/bash", "-c"]
    args:
    - |
      echo "--- Testing access to secrets in 'spring-petclinic' ---"

      # Get the ServiceAccount token from the pod
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      echo "ServiceAccount Token loaded."

      # Get the Kubernetes API server URL
      KUBERNETES_PORT_443_TCP_ADDR=${KUBERNETES_SERVICE_HOST}
      KUBERNETES_PORT_443_TCP_PORT=${KUBERNETES_SERVICE_PORT}
      KUBERNETES_API_URL="https://${KUBERNETES_PORT_443_TCP_ADDR}:${KUBERNETES_PORT_443_TCP_PORT}"
      echo "Kubernetes API URL: ${KUBERNETES_API_URL}"

      echo -e "\n--- Listing secrets in spring-petclinic (should succeed) ---"
      curl -s -k \
        -H "Authorization: Bearer $TOKEN" \
        ${KUBERNETES_API_URL}/api/v1/namespaces/spring-petclinic/secrets | jq .items[].metadata.name

      echo -e "\n--- Getting 'my-test-secret' from spring-petclinic (should succeed) ---"
      curl -s -k \
        -H "Authorization: Bearer $TOKEN" \
        ${KUBERNETES_API_URL}/api/v1/namespaces/spring-petclinic/secrets/my-test-secret | jq .data

      echo -e "\n--- Attempting to create a secret in spring-petclinic (should FAIL - Forbidden) ---"
      curl -s -k -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"forbidden-secret","namespace":"spring-petclinic"},"type":"Opaque","stringData":{"test":"forbidden"}}' \
        ${KUBERNETES_API_URL}/api/v1/namespaces/spring-petclinic/secrets

      echo -e "\n--- Testing access to secrets in 'app-namespace' (should succeed, by default) ---"
      curl -s -k \
        -H "Authorization: Bearer $TOKEN" \
        ${KUBERNETES_API_URL}/api/v1/namespaces/app-namespace/secrets | jq .items[].metadata.name

      echo -e "\n--- Attempting to create a secret in app-namespace (should succeed by default) ---"
      curl -s -k -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"allowed-secret","namespace":"app-namespace"},"type":"Opaque","stringData":{"test":"allowed"}}' \
        ${KUBERNETES_API_URL}/api/v1/namespaces/app-namespace/secrets

      sleep 300 # Keep the pod running for inspection
    # --- START of the crucial securityContext block for the Container ---
    securityContext:
      allowPrivilegeEscalation: false # Must be false for restricted SCC
      capabilities:
        drop:
          - ALL # Drop all Linux capabilities
    # --- END of the crucial securityContext block for the Container ---
  restartPolicy: Never # Pod will exit after commands, don't restart it
[root@ushift06 tmp]# oc create -f pod-test.yaml 
pod/secret-viewer-test-pod created
[root@ushift06 tmp]# 
~~~

4. Check the logs: 

~~~
[root@ushift06 tmp]# oc logs pod/secret-viewer-test-pod -n demo-app
--- Testing access to secrets in 'spring-petclinic' ---
ServiceAccount Token loaded.
Kubernetes API URL: https://10.43.0.1:443

--- Listing secrets in spring-petclinic (should succeed) ---
"my-test-secret"

--- Getting 'my-test-secret' from spring-petclinic (should succeed) ---
{
  "testkey": "dGVzdHZhbHVl"
}

--- Attempting to create a secret in spring-petclinic (should FAIL - Forbidden) ---
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:demo-app:my-serviceaccount\" cannot create resource \"secrets\" in API group \"\" in the namespace \"spring-petclinic\"",
  "reason": "Forbidden",
  "details": {
    "kind": "secrets"
  },
  "code": 403
}
--- Testing access to secrets in 'app-namespace' (should succeed, by default) ---
jq: error (at <stdin>:11): Cannot iterate over null (null)

--- Attempting to create a secret in app-namespace (should succeed by default) ---
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:demo-app:my-serviceaccount\" cannot create resource \"secrets\" in API group \"\" in the namespace \"app-namespace\"",
  "reason": "Forbidden",
  "details": {
    "kind": "secrets"
  },
  "code": 403

~~~
