local k = import 'kube.libsonnet';
local kubecfg = import 'kubecfg.libsonnet';

k + kubecfg {
  cluster:: self.parseYaml(std.extVar('cluster'))[0] {
    fqdn: '%s.%s.%s.%s' % [self.name, self.region, self.cloud_provider, self.dns_zone],
  },
  ContourIngress(
    name,
    namespace,
    app=name,
    cluster=null,
    contour='contour',  // which contour instance/subdomain to use
    contourDomain='outreach.cloud',  // which domain contour's dns record lives in
    host=null,
    ingressDomain='outreach.cloud',  // which domain to write dns to
    serviceName=name,
    servicePort='http',
    tlsSecret=null,
  ): self.Ingress(name, namespace, app=app) {

    local clusterName = if cluster != null then cluster else $.cluster.name,
    local defaultHost = '%s.%s.%s' % [name, clusterName, ingressDomain],
    local target = '%s.%s.%s' % [contour, clusterName, contourDomain],
    local rule = {
      host: if host != null then host else defaultHost,
      http: {
        paths: [{
          backend: {
            serviceName: serviceName,
            servicePort: servicePort,
          },
        }],
      },
    },
    local tls = {
      hosts: [if host != null then host else defaultHost],
      secretName: tlsSecret,
    },
    local tlsAnnotations = {
      'certmanager.k8s.io/cluster-issuer': 'letsencrypt-prod',
      'kubernetes.io/tls-acme': 'true',
    },

    metadata+: {
      annotations+: {
        'external-dns.alpha.kubernetes.io/target': target,
        'kubernetes.io/ingress.class': 'contour',
      } + (if tlsSecret != null then tlsAnnotations else {}),
    },
    spec+: {
      rules: [rule],
      [if tlsSecret != null then 'tls']: [tls],
    },
  },
}
