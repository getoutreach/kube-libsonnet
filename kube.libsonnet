// Generic library of Kubernetes objects
//
// Objects in this file follow the regular Kubernetes API object
// schema with two exceptions:
//
// ## Optional helpers
//
// A few objects have defaults or additional "helper" hidden
// (double-colon) fields that will help with common situations.  For
// example, `Service.target_pod` generates suitable `selector` and
// `ports` blocks for the common case of a single-pod/single-port
// service.  If for some reason you don't want the helper, just
// provide explicit values for the regular Kubernetes fields that the
// helper *would* have generated, and the helper logic will be
// ignored.
//
// ## The Underscore Convention:
//
// Various constructs in the Kubernetes API use JSON arrays to
// represent unordered sets or named key/value maps.  This is
// particularly annoying with jsonnet since we want to use jsonnet's
// powerful object merge operation with these constructs.
//
// To combat this, this library attempts to provide more "jsonnet
// native" variants of these arrays in alternative hidden fields that
// end with an underscore.  For example, the `env_` block in
// `Container`:
// ```
// kube.Container("foo") {
//   env_: { FOO: "bar" },
// }
// ```
// ... produces the expected `container.env` JSON array:
// ```
// {
//   "env": [
//     { "name": "FOO", "value": "bar" }
//   ]
// }
// ```
//
// If you are confused by the underscore versions, or don't want them
// in your situation then just ignore them and set the regular
// non-underscore field as usual.
//
//
// ## TODO
//
// TODO: Expand this to include all API objects.
//
// Should probably fill out all the defaults here too, so jsonnet can
// reference them.  In addition, jsonnet validation is more useful
// (client-side, and gives better line information).

{
  // Returns array of values from given object.  Does not include hidden fields.
  objectValues(o):: [o[field] for field in std.objectFields(o)],

  // Returns array of [key, value] pairs from given object.  Does not include hidden fields.
  objectItems(o):: [[k, o[k]] for k in std.objectFields(o)],

  // Replace all occurrences of `_` with `-`.
  hyphenate(s):: std.join('-', std.split(s, '_')),

  // Convert {foo: {a: b}} to [{name: foo, a: b}]
  mapToNamedList(o):: [{ name: $.hyphenate(n) } + o[n] for n in std.objectFields(o)],

  // Convert from SI unit suffixes to regular number
  siToNum(n):: (
    local convert =
      if std.endsWith(n, 'm') then [1, 0.001]
      else if std.endsWith(n, 'K') then [1, 1e3]
      else if std.endsWith(n, 'M') then [1, 1e6]
      else if std.endsWith(n, 'G') then [1, 1e9]
      else if std.endsWith(n, 'T') then [1, 1e12]
      else if std.endsWith(n, 'P') then [1, 1e15]
      else if std.endsWith(n, 'E') then [1, 1e18]
      else if std.endsWith(n, 'Ki') then [2, std.pow(2, 10)]
      else if std.endsWith(n, 'Mi') then [2, std.pow(2, 20)]
      else if std.endsWith(n, 'Gi') then [2, std.pow(2, 30)]
      else if std.endsWith(n, 'Ti') then [2, std.pow(2, 40)]
      else if std.endsWith(n, 'Pi') then [2, std.pow(2, 50)]
      else if std.endsWith(n, 'Ei') then [2, std.pow(2, 60)]
      else error 'Unknown numerical suffix in ' + n;
    local n_len = std.length(n);
    std.parseInt(std.substr(n, 0, n_len - convert[0])) * convert[1]
  ),

  _Object(apiVersion, kind, name, app=null, namespace=null):: {
    apiVersion: apiVersion,
    kind: kind,
    metadata: {
      annotations: {},
      labels: {
        name: name,
        [if app != null then 'app']: app,
        [if app != null && namespace == 'kube-system' then 'k8s-app']: app,
      },
      name: name,
      [if namespace != null then 'namespace']: namespace,
    },
  },

  List(): {
    apiVersion: 'v1',
    kind: 'List',
    items_:: {},
    items: $.objectValues(self.items_),
  },

  Namespace(name): $._Object('v1', 'Namespace', name) {
  },

  Endpoints(name): $._Object('v1', 'Endpoints', name) {
    Ip(addr):: { ip: addr },
    Port(p):: { port: p },

    subsets: [],
  },

  Service(name, namespace, app=name):
    $._Object('v1', 'Service', name, app=app, namespace=namespace) {
      local service = self,

      target_pod:: error 'service target_pod required',
      port:: self.target_pod.spec.containers[0].ports[0].containerPort,

      // Helpers that format host:port in various ways
      http_url:: 'http://%s.%s:%s/' % [
        self.metadata.name,
        self.metadata.namespace,
        self.spec.ports[0].port,
      ],
      proxy_urlpath:: '/api/v1/proxy/namespaces/%s/services/%s/' % [
        self.metadata.namespace,
        self.metadata.name,
      ],
      // Useful in Ingress rules
      name_port:: {
        serviceName: service.metadata.name,
        servicePort: service.spec.ports[0].port,
      },

      spec: {
        selector: service.target_pod.metadata.labels,
        ports: [
          {
            local target_port = service.target_pod.spec.containers[0].ports[0],
            name: target_port.name,
            port: service.port,
            targetPort: target_port.name,
          },
        ],
        type: 'ClusterIP',
      },
    },

  PersistentVolume(name): $._Object('v1', 'PersistentVolume', name) {
    spec: {},
  },

  PVCVolume(pvc): {
    persistentVolumeClaim: { claimName: pvc.metadata.name },
  },

  StorageClass(name): $._Object('storage.k8s.io/v1beta1', 'StorageClass', name) {
    provisioner: error 'provisioner required',
  },

  PersistentVolumeClaim(name, namespace, app=name):
    $._Object('v1', 'PersistentVolumeClaim', name, app=app, namespace=namespace) {
      local pvc = self,

      storageClass:: null,
      storage:: error 'storage required',

      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: pvc.storage,
          },
        },
        [if pvc.storageClass != null then 'storageClassName']: pvc.storageClass,
      },
    },

  Container(name): {
    name: name,
    image: error 'container image value required',

    envList(map):: [
      if std.type(map[x]) == 'object' then { name: x, valueFrom: map[x] } else { name: x, value: map[x] }
      for x in std.objectFields(map)
    ],

    env_:: {},
    env: self.envList(self.env_),

    args_:: {},
    args: ['--%s=%s' % kv for kv in $.objectItems(self.args_)],

    ports_:: {},
    ports: $.mapToNamedList(self.ports_),

    volumeMounts_:: {},
    volumeMounts: $.mapToNamedList(self.volumeMounts_),

    stdin: false,
    tty: false,
    assert !self.tty || self.stdin : 'tty=true requires stdin=true',
  },

  Pod(name): $._Object('v1', 'Pod', name) {
    spec: $.PodSpec,
  },

  PodSpec: {
    // The 'first' container is used in various defaults in k8s.
    default_container:: std.objectFields(self.containers)[0],
    //containers_:: {},

    //containers: [{ name: $.hyphenate(name) } + self.containers_[name] for name in [self.default_container] + [n for n in std.objectFields(self.containers_) if n != self.default_container]],

    //initContainers_:: {},
    //initContainers:
    //  [
    //    { name: $.hyphenate(name) } + self.initContainers_[name]
    //    for name in std.objectFields(self.initContainers_)
    //  ],

    volumes_:: {},
    volumes: $.mapToNamedList(self.volumes_),

    imagePullSecrets: [],

    terminationGracePeriodSeconds: 30,

    assert std.length(self.containers) > 0 : 'must have at least one container',
  },

  WeightedPodAffinityTerm(matchExpressions={}, matchLabels={}): {
    podAffinityTerm: {
      labelSelector: {
        [if std.length(matchExpressions) > 0 then 'matchExpressions']: $.mapToNamedList(matchExpressions),
        [if std.length(matchLabels) > 0 then 'matchLabels']: matchLabels,
      },
      topologyKey: 'kubernetes.io/hostname',
    },
    weight: 100,

    assert std.length(self.podAffinityTerm.labelSelector) == 1 : 'must pass either matchLabels or matchExpressions',
  },

  EmptyDirVolume(): {
    emptyDir: {},
  },

  HostPathVolume(path): {
    hostPath: { path: path },
  },

  GitRepoVolume(repository, revision): {
    gitRepo: {
      repository: repository,

      // "master" is possible, but should be avoided for production
      revision: revision,
    },
  },

  SecretVolume(secret): {
    secret: { secretName: secret.metadata.name },
  },

  ConfigMapVolume(configmap): {
    configMap: { name: configmap.metadata.name },
  },

  ConfigMap(name, namespace, app=name): $._Object('v1', 'ConfigMap', name, namespace=namespace, app=app) {
    data: {},

    // I keep thinking data values can be any JSON type.  This check
    // will remind me that they must be strings :(
    local nonstrings = [
      k
      for k in std.objectFields(self.data)
      if std.type(self.data[k]) != 'string'
    ],
    assert std.length(nonstrings) == 0 : 'data contains non-string values: %s' % [nonstrings],
  },

  // subtype of EnvVarSource
  ConfigMapRef(configmap, key): {
    assert std.objectHas(configmap.data, key) : '%s not in configmap.data' % [key],
    configMapKeyRef: {
      name: configmap.metadata.name,
      key: key,
    },
  },

  Secret(name, namespace, app=name): $._Object('v1', 'Secret', name, app=app, namespace=namespace) {
    local secret = self,

    type: 'Opaque',
    data_:: {},
    data: { [k]: std.base64(secret.data_[k]) for k in std.objectFields(secret.data_) },
  },

  // subtype of EnvVarSource
  SecretKeyRef(secret, key): {
    assert std.objectHas(secret.data, key) : '%s not in secret.data' % [key],
    secretKeyRef: {
      name: secret.metadata.name,
      key: key,
    },
  },

  // subtype of EnvVarSource
  FieldRef(key): {
    fieldRef: {
      apiVersion: 'v1',
      fieldPath: key,
    },
  },

  // subtype of EnvVarSource
  ResourceFieldRef(key): {
    resourceFieldRef: {
      resource: key,
      divisor_:: 1,
      divisor: std.toString(self.divisor_),
    },
  },

  VersionedDeployment(name, namespace, version, app=name):
    $.Deployment(name + '-' + version, namespace, app) {
      metadata+: { labels+: { version: version } },
    },

  Deployment(name, namespace, app=name):
    $._Object('extensions/v1beta1', 'Deployment', name, app=app, namespace=namespace) {
      local deployment = self,

      spec: {
        template: {
          spec: $.PodSpec,
          metadata: {
            labels: deployment.metadata.labels,
            annotations: {},
          },
        },

        strategy: {
          type: 'RollingUpdate',

          //local pvcs = [
          //  v
          //  for v in deployment.spec.template.spec.volumes
          //  if std.objectHas(v, 'persistentVolumeClaim')
          //],
          //local is_stateless = std.length(pvcs) == 0,

          // Apps trying to maintain a majority quorum or similar will
          // want to tune these carefully.
          // NB: Upstream default is surge=1 unavail=1
          //rollingUpdate: if is_stateless then {
          //  maxSurge: '25%',  // rounds up
          //  maxUnavailable: '25%',  // rounds down
          //} else {
          //  // Poor-man's StatelessSet.  Useful mostly with replicas=1.
          //  maxSurge: 0,
          //  maxUnavailable: 1,
          //},
        },

        replicas: 1,
        assert self.replicas >= 1,
      },
    },

  CrossVersionObjectReference(target): {
    apiVersion: target.apiVersion,
    kind: target.kind,
    name: target.metadata.name,
  },

  HorizontalPodAutoscaler(name): $._Object('autoscaling/v1', 'HorizontalPodAutoscaler', name) {
    local hpa = self,

    target:: error 'target required',

    spec: {
      scaleTargetRef: $.CrossVersionObjectReference(hpa.target),

      minReplicas: hpa.target.spec.replicas,
      maxReplicas: error 'maxReplicas required',

      assert self.maxReplicas >= self.minReplicas,
    },
  },

  StatefulSet(name): $._Object('apps/v1beta1', 'StatefulSet', name) {
    local sset = self,

    spec: {
      serviceName: name,

      template: {
        spec: $.PodSpec,
        metadata: {
          labels: sset.metadata.labels,
          annotations: {},
        },
      },

      volumeClaimTemplates_:: {},
      volumeClaimTemplates: [$.PersistentVolumeClaim($.hyphenate(kv[0])) + kv[1] for kv in $.objectItems(self.volumeClaimTemplates_)],

      replicas: 1,
      assert self.replicas >= 1,
    },
  },

  Job(name): $._Object('batch/v1', 'Job', name) {
    local job = self,

    spec: {
      template: {
        spec: $.PodSpec {
          restartPolicy: 'OnFailure',
        },
        metadata: {
          labels: job.metadata.labels,
          annotations: {},
        },
      },

      completions: 1,
      parallelism: 1,
    },
  },

  DaemonSet(name, namespace, app=name):
    $._Object('extensions/v1beta1', 'DaemonSet', name, app=app, namespace=namespace) {
      local ds = self,
      spec: {
        template: {
          metadata: {
            labels: ds.metadata.labels,
            annotations: {},
          },
          spec: $.PodSpec,
        },
      },
    },

  Ingress(name, namespace, app=name):
    $._Object('extensions/v1beta1', 'Ingress', name, app=app, namespace=namespace) {
      spec: {},
    },

  ThirdPartyResource(name): $._Object('extensions/v1beta1', 'ThirdPartyResource', name) {
    versions_:: [],
    versions: [{ name: n } for n in self.versions_],
  },

  ServiceAccount(name, namespace, app=name): $._Object('v1', 'ServiceAccount', name, namespace=namespace, app=app) {
  },

  Role(name, app=name): $._Object('rbac.authorization.k8s.io/v1', 'Role', name, app=app) {
    rules: [],
  },

  ClusterRole(name, app=name): $.Role(name, app=app) {
    kind: 'ClusterRole',
  },

  RoleBinding(name, app=name): $._Object('rbac.authorization.k8s.io/v1', 'RoleBinding', name, app=app) {
    local rb = self,

    subjects_:: [],
    subjects: [{
      kind: o.kind,
      namespace: o.metadata.namespace,
      name: o.metadata.name,
    } for o in self.subjects_],

    roleRef_:: error 'roleRef is required',
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: rb.roleRef_.kind,
      name: rb.roleRef_.metadata.name,
    },
  },

  ClusterRoleBinding(name, app=name): $.RoleBinding(name, app=app) {
    kind: 'ClusterRoleBinding',
  },

  APIService(name, app=name): $._Object('apiregistration.k8s.io/v1beta1', 'APIService', name, app=app) {
    local api = self,
    kind: 'APIService',
    service:: error 'service required',
    spec+: {
      group: std.split(name, '.')[0],
      version: std.join('.', std.split(name, '.')[1:]),
      service+: {
        name: api.service.metadata.name,
        namespace: api.service.metadata.namespace,
      },
    },
  },

  Mixins: {
    'cluster-service': {
      metadata+: {
        labels+: {
          'kubernetes.io/cluster-service': 'true',
        },
      },
    },
    'critical-pod': {
      metadata+: {
        annotations+: {
          'scheduler.alpha.kubernetes.io/critical-pod': '',
        },
      },
    },
  },
}
