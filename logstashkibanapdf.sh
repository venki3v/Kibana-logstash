date_diff=7
date_diff2=1

# Find the month of the start date
repstart_month=$(date "--date=${dataset_date} -${date_diff} day" +%b)

# Find the month of the end date
repend_month=$(date "--date=${dataset_date} -${date_diff2} day" +%b)

# Get report start date and report end date in format 2016-07-15
repstart_date=$(date "--date=${dataset_date} -${date_diff} day" +%Y-%m-%d)
repend_date=$(date "--date=${dataset_date} -${date_diff2} day" +%Y-%m-%d)
#print start date and end date
echo $repstart_date
echo $repend_date

# if start month and end month are same or clause has only one month otherwise it has both the months
if [ $repstart_month == $repend_month ] ; then
 echo "same month"
 syslogmonth=syslog_timestamp:$repstart_month*
 echo $syslogmonth
else
  orClause=" OR "
  syslogmonth=syslog_timestamp:\($repstart_month*$orClause$repend_month*\)
  echo $syslogmonth
fi

# Convert the report start date to logstash index format logstash-2015.07.16
newstartindexdate=`echo $repstart_date | tr "-" .`
newendindexdate=`echo $repend_date | tr "-" .`
newstartindexdate=${newstartindexdate:0:9}
newendindexdate=${newendindexdate:0:9}
echo $newstartindexdate
echo $newendindexdate
if [ $newstartindexdate == $newendindexdate ] ; then
    index_newname=logstash-$newstartindexdate*
else
    index_newname=logstash-$newendindexdate*,logstash-$newstartindexdate*
fi
echo $index_newname
#echo $index_name

// Create a temp file with curl query to local elastic search
cat > dcdcloudtemppdf.sh <<EOF
curl -XGET 'http://localhost:9200/${index_newname}/_search?pretty' -d '{
  "query": {
    "filtered": {
      "query": {
        "bool": {
          "should": [
            {
              "query_string": {
                "query": "syslog_program:sshd AND syslog_message:failure AND path:*2016* AND ${syslogmonth}"
              }
            }
          ]
        }
      },
      "filter": {
        "bool": {
          "must": [
            {
              "range": {
                "@timestamp": {
                  "gte": "${repstart_date}",
                  "lte": "${repend_date}"
                }
              }
            },
            {
              "fquery": {
                "query": {
                  "query_string": {
                      "query": "syslog_hostname:(*di01osp* OR *di01osc*)"
                  }
                },
                "_cache": true
              }
            }
          ]
        }
      }
    }
  },
  "highlight": {
    "fields": {},
    "fragment_size": 2147483647,
    "pre_tags": [
      "@start-highlight@"
    ],
    "post_tags": [
      "@end-highlight@"
    ]
  },
  "size": 500,
  "sort": [
    {
      "syslog_message": {
        "order": "desc"
      }
    },
    {
      "@timestamp": {
        "order": "desc"
      }
    }
  ]
}'     > dcdcloudjsonoutput
EOF
cat >> dcdcloudtemppdf.sh <<EOF
jq '.hits.hits[]._source.message' dcdcloudjsonoutput > dcdcloudmessageout
jq '.hits.hits[]._source.device_ip' dcdcloudjsonoutput > dcdcloudsyslogdeviceout
paste -d '|' dcdcloudmessageout dcdcloudsyslogdeviceout > dcdcloudcompsys.txt
if [ -s dcdcloudcompsys.txt ]; then
  filenoteempty=true
fi
nl dcdcloudcompsys.txt > dcdcloudcompsyscopy.txt
mv -f dcdcloudcompsyscopy.txt dcdcloudcompsys.txt
enscript -b "Authentication Failure report for DCD Cloud servers  from ${repstart_date} to ${repend_date}"  -p dcdcloudcompsys.ps dcdcloudcompsys.txt
ps2pdf dcdcloudcompsys.ps dcdcloudreportnew$repend_date.pdf
cp dcdcloudreportnew$repend_date.pdf /tmp/dcdcloudreportnew.pdf
echo \$filenotempty
if [ \$filenotempty ] ; then
   echo "DCD Authentication failure report for week ending  ${repend_date}" | mail -r logstash@logstash.ecap.com -a dcdcloudreportnew$repend_date.pdf  -s "DCD cloud  Authentication Failure report for week ending  ${repend_date}" -S smtp=smtp://mailhub.intra.com:25 vs@xx123.com
else
   echo "There are no DCD Authentication failure for week ending  ${repend_date}" | mail -r logstash@logstash.ecap.com -s "There are no DCD cloud  Authentication failure  for week ending  ${repend_date}" -S smtp=smtp://mailhub.intra.com:25 vs@xx123.com
fi

chmod 777 /tmp/dcdcloudreportnew.pdf
rm -f dcdcloudmessageout dcdcloudsyslogdeviceout dcdcloudcompsys.txt  dcdcloudreportnew$repend_date.pdf dcdcloudjsonoutput dcdcloudcompsys.ps
EOF
chmod 755 dcdcloudtemppdf.sh
cd /root/logstash-pdfreports
./dcdcloudtemppdf.sh

