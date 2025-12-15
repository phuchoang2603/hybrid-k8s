{{/* release name */}}
{{- define "capi-rke2-proxmox.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* cluster name */}}
{{- define "capi-rke2-proxmox.cluster-name" -}}
{{- default .Release.Name .Values.cluster.name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/* Common labels */}}
{{- define "capi-rke2-proxmox.labels" -}}
cluster.x-k8s.io/cluster-name: {{ include "capi-rke2-proxmox.cluster-name" . }}
{{- end -}}

{{/*
RKE2ConfigTemplate spec for worker nodes
*/}}
{{- define "rke2ConfigTemplateSpec" -}}
agentConfig:
  {{- if .nodePool.agentConfig }}
  {{- toYaml .nodePool.agentConfig | nindent 2 }}
  {{- end }}
{{- if .nodePool.preRKE2Commands }}
preRKE2Commands:
  {{- toYaml .nodePool.preRKE2Commands | nindent 2 }}
{{- end }}
{{- if .nodePool.postRKE2Commands }}
postRKE2Commands:
  {{- toYaml .nodePool.postRKE2Commands | nindent 2 }}
{{- end }}
{{- if .nodePool.files }}
files:
  {{- toYaml .nodePool.files | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Calculates a SHA256 hash of the RKE2ConfigTemplate content for rolling updates
*/}}
{{- define "rke2ConfigTemplateHash" -}}
{{- $templateContent := include "rke2ConfigTemplateSpec" . -}}
{{- $templateContent | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
ProxmoxMachineTemplate spec
*/}}
{{- define "ProxmoxMachineTemplateSpec" -}}
{{- if .nodePool.allowedNodes }}
allowedNodes:
{{- range .nodePool.allowedNodes }}
- {{ . }}
{{- end }}
{{- else }}
allowedNodes:
{{- range .Global.Values.cluster.allowedNodes }}
- {{ . }}
{{- end }}
{{- end }}
disks:
  bootVolume:
    disk: {{ .nodePool.disks.bootVolume.disk }}
    sizeGb: {{ .nodePool.disks.bootVolume.sizeGb }}
storage: {{ .nodePool.storage }}
format: {{ .nodePool.format | default "qcow2" }}
full: {{ .nodePool.full | default true }}
network:
  default:
    {{- if and .nodePool.network.addressesFromPools .nodePool.network.addressesFromPools.enabled }}
    {{- if .Global.Values.ipamProvider.enabled }}
    ipv4PoolRef:
      apiGroup: ipam.cluster.x-k8s.io
      kind: InClusterIPPool
      name: {{ include "capi-rke2-proxmox.cluster-name" .Global }}-ipam-pool
    {{- end }}
    {{- end }}
    dnsServers:
    {{- range .nodePool.network.dnsServers }}
    - {{ . }}
    {{- end }}
    bridge: {{ .nodePool.network.bridge }}
    model: {{ .nodePool.network.model | default "virtio" }}
memoryMiB: {{ .nodePool.memoryMiB }}
numCores: {{ .nodePool.numCores }}
numSockets: {{ .nodePool.numSockets }}
{{- if .nodePool.sourceNode }}
sourceNode: {{ .nodePool.sourceNode }}
{{- end }}
{{- if .nodePool.pool }}
pool: {{ .nodePool.pool }}
{{- end }}
{{- if .nodePool.templateId }}
templateID: {{ .nodePool.templateId }}
{{- else if .nodePool.templateSelector }}
templateSelector:
  matchTags:
  {{- range .nodePool.templateSelector.matchTags }}
  - {{ . }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Calculates a SHA256 hash of the ProxmoxMachineTemplate content for rolling updates
*/}}
{{- define "ProxmoxMachineTemplateHash" -}}
{{- $templateContent := include "ProxmoxMachineTemplateSpec" . -}}
{{- $templateContent | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
ProxmoxMachineTemplate spec for control plane
Uses the first nodePool or dedicated controlPlane.machineTemplate config
*/}}
{{- define "ControlPlaneMachineTemplateSpec" -}}
{{- $nodePool := index .Global.Values.nodePools 0 -}}
{{- if $nodePool.allowedNodes }}
allowedNodes:
{{- range $nodePool.allowedNodes }}
- {{ . }}
{{- end }}
{{- else }}
allowedNodes:
{{- range .Global.Values.cluster.allowedNodes }}
- {{ . }}
{{- end }}
{{- end }}
disks:
  bootVolume:
    disk: {{ $nodePool.disks.bootVolume.disk }}
    sizeGb: {{ $nodePool.disks.bootVolume.sizeGb }}
storage: {{ $nodePool.storage }}
format: {{ $nodePool.format | default "qcow2" }}
full: {{ $nodePool.full | default true }}
network:
  default:
    dnsServers:
    {{- range $nodePool.network.dnsServers }}
    - {{ . }}
    {{- end }}
    bridge: {{ $nodePool.network.bridge }}
    model: {{ $nodePool.network.model | default "virtio" }}
memoryMiB: {{ $nodePool.memoryMiB }}
numCores: {{ $nodePool.numCores }}
numSockets: {{ $nodePool.numSockets }}
{{- if $nodePool.sourceNode }}
sourceNode: {{ $nodePool.sourceNode }}
{{- end }}
{{- if $nodePool.pool }}
pool: {{ $nodePool.pool }}
{{- end }}
{{- if $nodePool.templateId }}
templateID: {{ $nodePool.templateId }}
{{- else if $nodePool.templateSelector }}
templateSelector:
  matchTags:
  {{- range $nodePool.templateSelector.matchTags }}
  - {{ . }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Calculates a SHA256 hash of the control plane ProxmoxMachineTemplate content
*/}}
{{- define "ControlPlaneMachineTemplateHash" -}}
{{- $templateContent := include "ControlPlaneMachineTemplateSpec" . -}}
{{- $templateContent | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
Generate kube-vip manifest command
*/}}
{{- define "capi-rke2-proxmox.kubeVipCommand" -}}
{{- $address := .Values.cluster.controlPlaneEndpoint.host }}
{{- $version := .Values.cluster.controlPlane.kubeVip.version | default "v0.8.0" }}
{{- printf "mkdir -p /var/lib/rancher/rke2/server/manifests/ && ctr images pull ghcr.io/kube-vip/kube-vip:%s && ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:%s vip /kube-vip manifest daemonset --arp --interface $(ip -4 -j route list default | jq -r .[0].dev) --address %s --controlplane --leaderElection --taint --services --inCluster | tee /var/lib/rancher/rke2/server/manifests/kube-vip.yaml" $version $version $address }}
{{- end }}

{{/*
Generate kube-vip RBAC manifest
*/}}
{{- define "capi-rke2-proxmox.kubeVipRBAC" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-vip
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  name: system:kube-vip-role
rules:
  - apiGroups: [""]
    resources: ["services", "services/status", "nodes", "endpoints"]
    verbs: ["list","get","watch", "update"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["list", "get", "watch", "update", "create"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:kube-vip-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-vip-role
subjects:
- kind: ServiceAccount
  name: kube-vip
  namespace: kube-system
{{- end }}
