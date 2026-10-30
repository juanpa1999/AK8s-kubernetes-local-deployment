kubectl apply -f secret.yml

kubectl apply -f dp-db.yaml

sleep 5

kubectl apply -f dp-back.yaml

sleep 2

kubectl apply -f dp-front.yaml

sleep 30

# wait until Postgres accepts connections, otherwise alembic/seed fail on a cold start
until kubectl exec deploy/db-deployment -- pg_isready -U postgres -d postgres > /dev/null 2>&1; do
  echo "waiting for db..."
  sleep 2
done

kubectl exec -it $(kubectl get pods -l app=back -o jsonpath="{.items[0].metadata.name}") -- alembic upgrade head

# seed test data (user pablodevops, sensors, readings); needs the tables created by alembic above
kubectl exec -i deploy/db-deployment -- psql -U postgres -d postgres -v ON_ERROR_STOP=1 < sql/seed_pablodevops.sql

# port-forward back (8000) and front (3000) to localhost; Ctrl+C stops both
kubectl port-forward svc/back-service 8000:8000 &
BACK_PF_PID=$!
kubectl port-forward svc/front-service 3000:3000 &
FRONT_PF_PID=$!
trap 'kill $BACK_PF_PID $FRONT_PF_PID 2>/dev/null' INT TERM EXIT
echo "back:  http://localhost:8000"
echo "front: http://localhost:3000"
wait


#user: pablodevops pass: Test123456789*

#to generate the dockerhub secret, run the following command and replace the username and access token with your own. Then copy the output and paste it in the secret.yml file in the .dockerconfigjson field. 
#echo -n '{"auths":{"https://index.docker.io/v1/":{"username":"TU_USUARIO","password":"TU_ACCESS_TOKEN","auth":"'$(echo -n 'TU_USUARIO:TU_ACCESS_TOKEN' | base64 | tr -d '\n')'"}}}' | base64 | tr -d '\n'