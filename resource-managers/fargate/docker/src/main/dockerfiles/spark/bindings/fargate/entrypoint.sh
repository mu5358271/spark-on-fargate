#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# echo commands to the terminal output
set -ex

SPARK_CLASSPATH="$SPARK_CLASSPATH:${SPARK_HOME}/jars/*"
env | grep SPARK_JAVA_OPT_ | sort -t_ -k4 -n | sed 's/[^=]*=\(.*\)/\1/g' > /tmp/java_opts.txt
readarray -t SPARK_EXECUTOR_JAVA_OPTS < /tmp/java_opts.txt

if [ -n "$SPARK_EXTRA_CLASSPATH" ]; then
  SPARK_CLASSPATH="$SPARK_CLASSPATH:$SPARK_EXTRA_CLASSPATH"
fi

if [ "$PYSPARK_MAJOR_PYTHON_VERSION" == "2" ]; then
    pyv="$(python -V 2>&1)"
    export PYTHON_VERSION="${pyv:7}"
    export PYSPARK_PYTHON="python"
    export PYSPARK_DRIVER_PYTHON="python"
elif [ "$PYSPARK_MAJOR_PYTHON_VERSION" == "3" ]; then
    pyv3="$(python3 -V 2>&1)"
    export PYTHON_VERSION="${pyv3:7}"
    export PYSPARK_PYTHON="python3"
    export PYSPARK_DRIVER_PYTHON="python3"
fi

if ! [ -z ${HADOOP_CONF_DIR+x} ]; then
  SPARK_CLASSPATH="$HADOOP_CONF_DIR:$SPARK_CLASSPATH";
fi

case "$1" in
  driver)
    shift 1
    CMD=(
      "$SPARK_HOME/bin/spark-submit"
      --conf "spark.driver.bindAddress=${SPARK_DRIVER_BIND_ADDRESS:-$(hostname)}"
      --deploy-mode client
      "$@"
    )
    ;;
  executor)
    shift 1
    if [[ -z ${SPARK_EXECUTOR_ID} ]];then
      TASK_ARN=$(curl --silent --fail --connect-timeout 5 --max-time 5 --retry 3 http://169.254.170.2/v2/metadata | jq -r '.TaskARN')
      SPARK_EXECUTOR_ID=${TASK_ARN##*/}
    fi
    CMD=(
      ${JAVA_HOME}/bin/java
      "${SPARK_EXECUTOR_JAVA_OPTS[@]}"
      -Xms$SPARK_EXECUTOR_MEMORY
      -Xmx$SPARK_EXECUTOR_MEMORY
      -cp "$SPARK_CLASSPATH"
      org.apache.spark.executor.CoarseGrainedExecutorBackend
      --driver-url $SPARK_DRIVER_URL
      --executor-id $SPARK_EXECUTOR_ID
      --cores $SPARK_EXECUTOR_CORES
      --app-id $SPARK_APPLICATION_ID
      --hostname ${SPARK_EXECUTOR_HOSTNAME:-$(hostname)}
    )
    ;;
  *)
    echo "Non-spark command provided, proceeding in pass-through mode..."
    CMD=("$@")
    ;;
esac

# Execute the container CMD under tini for better hygiene
exec /sbin/tini -s -- "${CMD[@]}"
