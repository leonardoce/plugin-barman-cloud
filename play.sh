#!/usr/bin/env bash

set -eu

CLUSTER_NAME=cluster-example
MINIO_POD_NAME=$(kubectl get pods -l app=minio -o "jsonpath={.items[].metadata.name}")
STEPS=25

wait_until_archive() {
  count=0
  while [ $count -le 300 ]; do
    how_many_wals=$(kubectl exec ${CLUSTER_NAME}-1 -c postgres -- ls /var/lib/postgresql/data/pgdata/pg_wal/archive_status/ | grep ready | wc -l)
    echo "Archiving $how_many_wals"
    if [ $how_many_wals -eq 0 ]; then
      break
    fi
    sleep 1
  done
}

# Wait until there's nothing to archive
echo "Preparation"
wait_until_archive

# Clean up everything and do something against the database
start_work=$(date +%s)
kubectl exec ${MINIO_POD_NAME} -c minio -- rm -rf /data/backups/cluster-example/wals
kubectl exec ${CLUSTER_NAME}-1 -c postgres -- psql -c "TRUNCATE TABLE test" || :
kubectl exec ${CLUSTER_NAME}-1 -c postgres -- psql -c "DROP TABLE test" || :
kubectl exec ${CLUSTER_NAME}-1 -c postgres -- psql -c 'CREATE TABLE test (i serial primary key, t text)'
kubectl exec ${CLUSTER_NAME}-1 -c postgres -- psql -c "INSERT INTO test (t) VALUES (md5('x'))"
for i in $(seq 0 $STEPS); do
  kubectl exec ${CLUSTER_NAME}-1 -c postgres -- psql -c "INSERT INTO test (t) SELECT md5(t) from test"
done
end_work=$(date +%s)

# Check until we archived everything
wait_until_archive
end_archiving=$(date +%s)

echo "Workload time: $(($end_work - $start_work))"
echo "Archiving time: $(($end_archiving - $end_work))"
echo "Elapsed time: $(($end_archiving - $start_work))"

created_wals=$(kubectl exec ${MINIO_POD_NAME} -- ls -R /data/backups/cluster-example/ | grep gz: | wc -l)
echo "Created $created_wals WALs"
