#!/bin/bash

set -euo pipefail

IFS=''

FILENAME="/etc/kubernetes/manifests/kube-apiserver.yaml"
AUDIT_TYPE="static"

if grep audit-dynamic-configuration "$FILENAME" ; then
	echo audit-dynamic-configuration patch already applied
	exit 0
fi

TMPFILE="/tmp/kube-apiserver.yaml.patched"
rm -f "$TMPFILE"

APISERVER_PREFIX="    -"
APISERVER_LINE="- kube-apiserver"

while read -r LINE
do
    echo "$LINE" >> "$TMPFILE"
    case "$LINE" in
        *$APISERVER_LINE*)
			echo "$APISERVER_PREFIX --audit-log-path=/var/lib/k8s_audit/audit.log" >> "$TMPFILE"
			echo "$APISERVER_PREFIX --audit-policy-file=/var/lib/k8s_audit/audit-policy.yaml" >> "$TMPFILE"
			echo "$APISERVER_PREFIX --audit-webhook-config-file=/var/lib/k8s_audit/webhook-config.yaml" >> "$TMPFILE"
            ;;
        *"volumeMounts:"*)
			echo "    - mountPath: /var/lib/k8s_audit/" >> "$TMPFILE"
			echo "      name: data" >> "$TMPFILE"
            ;;
        *"volumes:"*)
			echo "  - hostPath:" >> "$TMPFILE"
			echo "      path: /var/lib/k8s_audit" >> "$TMPFILE"
			echo "    name: data" >> "$TMPFILE"
            ;;

    esac
done < "$FILENAME"

cp "$FILENAME" "/tmp/kube-apiserver.yaml.original"
cp "$TMPFILE" "$FILENAME"