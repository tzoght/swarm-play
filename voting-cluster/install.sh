#!/bin/bash
MINPARAMS=0
echo "running script  \"`basename $0`\" with \"$*\"  "

createMachines ()
{
  echo ${1} ${2}
  docker-machine create -d virtualbox ${1}-manager

  for ((i=1 ; i<=${2} ; i++))
  do
    echo "DockerMachine - ${1}-agent-${i}"
    docker-machine create -d virtualbox ${1}-agent-${i}
  done
}



provisionCluster ()
{

  # start a swarm container on manager
  echo "Provisioning manager..."
  docker-machine ls
  docker run -d -p 3376:3376 -t -v /var/lib/boot2docker:/certs:ro\
  swarm manage -H 0.0.0.0:3376 --tlsverify --tlscacert=/certs/ca.pem\
   --tlscert=/certs/server.pem --tlskey=/certs/server-key.pem\
  token://${TOKEN}
  # Moving on to the agents
  echo "Provisioning agents..."
  for ((i=1 ; i<=${2} ; i++))
  do
    eval $(docker-machine env ${1}-agent-${i})
    docker run -d swarm join --addr=$(docker-machine ip ${1}-agent-${i}):2376 token://${TOKEN}
    echo "DockerMachine - ${1}-agent-${i}"
  done
}


createKeyStore()
{
  # create docker-machine for keystore
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
  --engine-opt="label=com.function=consul"  keystore
  eval $(docker-machine env keystore)
  # install things
  eval $(docker-machine env keystore)
  # consul
  docker run --restart=unless-stopped -d -p 8500:8500 -h consul progrium/consul -server -bootstrap
  # test it
  curl $(docker-machine ip keystore):8500/v1/catalog/nodes

}

createSwarmManager()
{
  # create the cluster manager
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
  --engine-opt="label=com.function=manager" \
  --engine-opt="cluster-store=consul://$(docker-machine ip keystore):8500" \
  --engine-opt="cluster-advertise=eth1:2376" manager
  # install things
  eval $(docker-machine env manager)
  # swarm manager
  docker run --restart=unless-stopped -d -p 3376:2375 \
    -v /var/lib/boot2docker:/certs:ro \
    swarm manage --tlsverify \
    --tlscacert=/certs/ca.pem \
    --tlscert=/certs/server.pem \
    --tlskey=/certs/server-key.pem \
    consul://$(docker-machine ip keystore):8500
    echo "Test the setup with Consul"
    echo "> docker-machine ssh manager"
    echo "> tail /var/lib/boot2docker/docker.log"
}


createLoadBalancer()
{
   rm -f config.toml
   echo "
    ListenAddr = \":8080\"
    DockerURL = \"tcp://$(docker-machine ip manager):3376\"
    TLSCACert = \"/var/lib/boot2docker/ca.pem\"
    TLSCert = \"/var/lib/boot2docker/server.pem\"
    TLSKey = \"/var/lib/boot2docker/server-key.pem\"

    [[Extensions]]
    Name = \"nginx\"
    ConfigPath = \"/etc/conf/nginx.conf\"
    PidPath = \"/etc/conf/nginx.pid\"
    MaxConn = 1024
    Port = 80 " >> config.toml

    # Create machine for load balancer
    docker-machine create -d virtualbox --virtualbox-memory "2000" \
        --engine-opt="label=com.function=interlock" loadbalancer
    eval $(docker-machine env loadbalancer)
    # Start an interlock container
    docker run \
    -P \
    -d \
    -ti \
    -v nginx:/etc/conf \
    -v /var/lib/boot2docker:/var/lib/boot2docker:ro \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(pwd)/config.toml:/etc/config.toml \
    --name interlock \
    ehazlett/interlock:1.0.1 \
    -D run -c /etc/config.toml
    # Start an nginx container on the load balancer
    docker run -ti -d \
    -p 80:80 \
    --label interlock.ext.name=nginx \
    --link=interlock:interlock \
    -v nginx:/etc/conf \
    --name nginx \
    nginx nginx -g "daemon off;" -c /etc/conf/nginx.conf
}

createSwarmNodes () {
  # frontend01
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
    --engine-opt="label=com.function=frontend01" \
    --engine-opt="cluster-store=consul://$(docker-machine ip keystore):8500" \
    --engine-opt="cluster-advertise=eth1:2376" frontend01
  eval $(docker-machine env frontend01)
  docker run -d swarm join --addr=$(docker-machine ip frontend01):2376 consul://$(docker-machine ip keystore):8500
  # frontend02
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
    --engine-opt="label=com.function=frontend02" \
    --engine-opt="cluster-store=consul://$(docker-machine ip keystore):8500" \
    --engine-opt="cluster-advertise=eth1:2376" frontend02
  eval $(docker-machine env frontend02)
  docker run -d swarm join --addr=$(docker-machine ip frontend02):2376 consul://$(docker-machine ip keystore):8500
  # worker01
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
    --engine-opt="label=com.function=worker01" \
    --engine-opt="cluster-store=consul://$(docker-machine ip keystore):8500" \
    --engine-opt="cluster-advertise=eth1:2376" worker01
  eval $(docker-machine env worker01)
  docker run -d swarm join --addr=$(docker-machine ip worker01):2376 consul://$(docker-machine ip keystore):8500
  # create the dbstore
  docker-machine create -d virtualbox --virtualbox-memory "2000" \
    --engine-opt="label=com.function=dbstore" \
    --engine-opt="cluster-store=consul://$(docker-machine ip keystore):8500" \
    --engine-opt="cluster-advertise=eth1:2376" dbstore
  eval $(docker-machine env dbstore)
  docker run -d swarm join --addr=$(docker-machine ip dbstore):2376 consul://$(docker-machine ip keystore):8500

}

setupVolumeAndNetwork () {

  eval $(docker-machine env dbstore)
  docker network ls
  eval $(docker-machine env manager)
  docker network create -d overlay voteapp
  eval $(docker-machine env dbstore)
  docker network ls
  docker volume create --name db-data
}

startServicesFromSwarmManager () {
  # From Swarm
  # postgres
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -v db-data:/var/lib/postgresql/data \
    -e constraint:com.function==dbstore \
    --net="voteapp" \
    --name db postgres:9.4
  # Redis
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -p 6379:6379 \
    -e constraint:com.function==dbstore \
    --net="voteapp" \
    --name redis redis
  # Worker01
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -e constraint:com.function==worker01 \
    --net="voteapp" \
    --net-alias=workers \
    --name worker01 docker/example-voting-app-worker
  # results application
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -p 80:80 \
    --label=interlock.hostname=results \
    --label=interlock.domain=myenterprise.com \
    -e constraint:com.function==dbstore \
    --net="voteapp" \
    --name results-app mtpgale/example-voting-app.result-app
  # voting appliation 1
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -p 80:80 \
    --label=interlock.hostname=vote \
    --label=interlock.domain=myenterprise.com \
    -e constraint:com.function==frontend01 \
    --net="voteapp" \
    --name voting-app01 mtpgale/example-voting-app.voting-app
  # voting application 2
  docker -H $(docker-machine ip manager):3376 run -t -d \
    -p 80:80 \
    --label=interlock.hostname=vote \
    --label=interlock.domain=myenterprise.com \
    -e constraint:com.function==frontend02 \
    --net="voteapp" \
    --name voting-app02 mtpgale/example-voting-app.voting-app
}

finishingTouches () {
  eval $(docker-machine env loadbalancer)
  docker exec interlock cat /etc/conf/nginx.conf
  docker restart nginx
  echo "To vote go to http://$(docker-machine ip frontend01)"
  echo "To view votes go to http://$(docker-machine ip dbstore)"
}

if [ $# -lt "$MINPARAMS" ]
then
  echo
  echo "This script needs at least $MINPARAMS command-line arguments!"
  echo "$0 namespaceprefix numOfAgents"
  echo "where:"
  echo "   namespaceprefix: a string to prefix swarm machines"
  echo "   numOfAgents: number of agents to deploy"
  exit -1
fi
echo "Excecuting: "
createKeyStore
createSwarmManager
createLoadBalancer
createSwarmNodes
setupVolumeAndNetwork
startServicesFromSwarmManager
finishingTouches
exit 0
