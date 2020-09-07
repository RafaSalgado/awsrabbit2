#! /bin/bash 

STATS2READ=( messages consumers ) 

# 

  

# Namespace 

NS=${NS:-"RabbitMQ"} 

REGION=${REGION:-"us-east-1"} 

# AvailabilityZone 

#az=$(ec2metadata --availability-zone) 

# Instance ID 

EC2ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)  

  

# Enable debug 

DEBUG=${DEBUG:-0} 

# Debug files 

DBGFILE=/tmp/rabbitmq2cloudwatch.debug 

if [[ $DEBUG == 0 ]]; then DBGFILE=/dev/null; fi 

  

date -uIns >> $DBGFILE 

  

# Collecting statistics for RabbitMQ queues 

# UNIT=Count 

  

declare -A TOTALS=( [messages]=0 [consumers]=0 ) 

  

for STATISTIC in "${STATS2READ[@]}"; do 

# Metric data is stored in $MDATA[12]. It is populated while parsing output of rabbitmqctl 

MDATA1='' 

MDATA2='' 

  

# Parsing output of rabbitmqctl  

while read -r line ; do 

echo "Processing line: $line" >> $DBGFILE 

read VALUE QUEUE <<< $line 

if [[ "$QUEUE" =~ ^amq\..* ]]; then 

                    continue 

                fi 

 

(( TOTALS[$STATISTIC] += $VALUE )) 

 

# Adding datapoint to aggregated metric 

# MetricName=$STATISTIC,Value=$VALUE,Unit=Count,Dimensions=[{Name=Queue,Value=$QUEUE}] 

MDATA1+="MetricName=$STATISTIC,Value=$VALUE,Unit=Count,Dimensions=[{Name=Queue,Value=$QUEUE}] " 

# Adding datapoint to instance-specific metric 

# MetricName=$STATISTIC,Value=$VALUE,Unit=Count,Dimensions=[{Name=Queue,Value=$QUEUE},{Name=InstanceId,Value=$EC2ID}]	 

MDATA2+="MetricName=$STATISTIC,Value=$VALUE,Unit=Count,Dimensions=[{Name=Queue,Value=$QUEUE},{Name=InstanceId,Value=$EC2ID}] " 

done < <(sudo rabbitmqctl list_queues $STATISTIC name -q) 

  

# Submitting metric data 1 

# It is not possible to submit more than 20 datapoints at time while using shorthand syntax 

echo "Submitting metric data: $MDATA1" >> $DBGFILE 

aws cloudwatch put-metric-data --namespace $NS --region $REGION --metric-data $MDATA1 >>$DBGFILE 2>&1 

  

# Submitting metric data 2 

# It is not possible to submit more than 20 datapoints at time while using shorthand syntax 

echo "Submitting metric data: $MDATA2" >> $DBGFILE 

aws cloudwatch put-metric-data --namespace $NS --region $REGION --metric-data $MDATA2 >>$DBGFILE 2>&1  

 

done 

  

# Submitting metric totals 

MTOTALS='' 

CLUSTERNAME=$(echo $NS | sed 's/.*\///') 

for K in "${!TOTALS[@]}"; 

do 

    MTOTALS+="MetricName=Total${K^},Value=${TOTALS[$K],Unit=Count,Dimensions=[{Name=Cluster,Value=$CLUSTERNAME}] " 

done 

aws cloudwatch put-metric-data --namespace $NS --region $REGION --metric-data $MTOTALS >>$DBGFILE 2>&1  

# Looking for partitioning of rabbitmq cluster (split brain) 

STATISTIC=partitioned 

clusterOK=$(sudo rabbitmqctl cluster_status | grep "{partitions,\[\]}" | wc -l) 

if [[ $clusterOK != "1" ]]; then 

    echo "RabbitMQ cluster is partitioned (split brain)!" >> $DBGFILE 

MDATA="MetricName=$STATISTIC,Value=1,Dimensions=[{Name=Cluster,Value=$CLUSTERNAME}] " 

else 

    echo "RabbitMQ cluster is OK (not partitioned)" >> $DBGFILE 

MDATA="MetricName=$STATISTIC,Value=0,Dimensions=[{Name=Cluster,Value=$CLUSTERNAME}] " 

fi 

# Submitting metric data 

echo "Submitting metric data: $MDATA" >> $DBGFILE 

aws cloudwatch put-metric-data --namespace $NS --region $REGION --metric-data $MDATA 2>&1 >>$DBGFILE 
