See https://kubernetes.io/docs/concepts/security/service-accounts/#cross-namespace


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

2. Define a Role and a Role binding (in the target namespace) that grants "view" access to secrets:

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
Raw output for spring-petclinic secrets:
{
  "kind": "SecretList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "2569775"
  },
  "items": [
    {
      "metadata": {
        "name": "my-test-secret",
        "namespace": "spring-petclinic",
        "uid": "aa976af4-b24b-4a19-a287-75ac08f804e2",
        "resourceVersion": "2568604",
        "creationTimestamp": "2025-05-28T08:54:09Z",
        "managedFields": [
          {
            "manager": "kubectl-create",
            "operation": "Update",
            "apiVersion": "v1",
            "time": "2025-05-28T08:54:09Z",
            "fieldsType": "FieldsV1",
            "fieldsV1": {
              "f:data": {
                ".": {},
                "f:testkey": {}
              },
              "f:type": {}
            }
          }
        ]
      },
      "data": {
        "testkey": "dGVzdHZhbHVl"
      },
      "type": "Opaque"
    }
  ]
}
Parsed names:
"my-test-secret"

--- Getting 'my-test-secret' from spring-petclinic (should succeed) ---
Raw output for my-test-secret:
{
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
    "name": "my-test-secret",
    "namespace": "spring-petclinic",
    "uid": "aa976af4-b24b-4a19-a287-75ac08f804e2",
    "resourceVersion": "2568604",
    "creationTimestamp": "2025-05-28T08:54:09Z",
    "managedFields": [
      {
        "manager": "kubectl-create",
        "operation": "Update",
        "apiVersion": "v1",
        "time": "2025-05-28T08:54:09Z",
        "fieldsType": "FieldsV1",
        "fieldsV1": {
          "f:data": {
            ".": {},
            "f:testkey": {}
          },
          "f:type": {}
        }
      }
    ]
  },
  "data": {
    "testkey": "dGVzdHZhbHVl"
  },
  "type": "Opaque"
}
Parsed data:
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
--- Testing access to secrets in 'demo-app' (should succeed, by default) ---
Raw output for demo-app secrets:
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:demo-app:my-serviceaccount\" cannot list resource \"secrets\" in API group \"\" in the namespace \"demo-app\"",
  "reason": "Forbidden",
  "details": {
    "kind": "secrets"
  },
  "code": 403
}
Parsed names:
jq: error (at <stdin>:12): Cannot iterate over null (null)
jq failed for demo-app

--- Attempting to create a secret in demo-app (should succeed by default) ---
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:demo-app:my-serviceaccount\" cannot create resource \"secrets\" in API group \"\" in the namespace \"demo-app\"",
  "reason": "Forbidden",
  "details": {
    "kind": "secrets"
  },
  "code": 403
~~~
