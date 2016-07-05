#!/bin/bash
MINPARAMS=2
echo "running script  \"`basename $0`\" with \"$*\"  "


destroyMachines ()
{
  echo "removing ${1}_manager"
  docker-machine rm -f  ${1}-manager
  for ((i=1 ; i<=${2} ; i++))
  do
    echo "removing ${1}-agent-${i}"
    docker-machine rm -f ${1}-agent-${i}
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
