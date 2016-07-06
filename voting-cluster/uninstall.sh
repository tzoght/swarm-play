#!/bin/bash
MINPARAMS=0
echo "running script  \"`basename $0`\" with \"$*\"  "


destroyMachines ()
{
  machines="dbstore frontend01 frontend02 keystore loadbalancer manager worker01"
  for machine in ${machines}
  do
    echo "removing ${machine}"
    docker-machine rm -f ${machine}
  done
}




if [ $# -lt "$MINPARAMS" ]
then
  echo
  echo "This script needs at least $MINPARAMS command-line arguments!"
  echo "$0 namespaceprefix numOfAgents"
  echo "where:"
  echo "   namespaceprefix: a string to prefix swarm machines"
  echo "   numOfAgents: number of agents to delete"
  exit -1
fi
echo "Excecuting: "
# createMachines $1 $2
destroyMachines $1 $2
exit 0
