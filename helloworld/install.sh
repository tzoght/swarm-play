#!/bin/bash
MINPARAMS=2
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
  # get the cluster token
  eval $(docker-machine env ${1}-manager)
  read TOKEN <<< `docker run --rm swarm create`
  echo "TOKEN is = ${TOKEN}"
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
createMachines $1 $2
provisionCluster $1 $2
export DOCKER_HOST=$(docker-machine ip ${1}-manager):3376
docker info
echo "export DOCKER_HOST=$(docker-machine ip ${1}-manager):3376"
exit 0
