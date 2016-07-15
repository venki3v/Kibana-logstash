cd /root/logstash-pdfreports
date_diff=7
date_diff2=1
repstart_month=$(date "--date=${dataset_date} -${date_diff} day" +%b)
repend_month=$(date "--date=${dataset_date} -${date_diff2} day" +%b)
#repend_month=Jul
#echo $repend_month
repstart_date=$(date "--date=${dataset_date} -${date_diff} day" +%Y-%m-%d)
repend_date=$(date "--date=${dataset_date} -${date_diff2} day" +%Y-%m-%d)
echo $repstart_date
echo $repend_date
if [ $repstart_month == $repend_month ] ; then
 echo "same month"
 syslogmonth=syslog_timestamp:$repstart_month*
 echo $syslogmonth
else
  orClause=" OR "
  syslogmonth=syslog_timestamp:\($repstart_month*$orClause$repend_month*\)
  echo $syslogmonth
fi
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
   echo "DCD Authentication failure report for week ending  ${repend_date}" | mail -r logstash@logstash.ecap.tdaf.com -a dcdcloudreportnew$repend_date.pdf  -s "DCD cloud  Authentication Failure report for week ending  ${repend_date}" -S smtp=smtp://mailhub.intra.com:25 vs@xx123.com
else
   echo "There are no DCD Authentication failure for week ending  ${repend_date}" | mail -r logstash@logstash.ecap.tdaf.com -s "There are no DCD cloud  Authentication failure  for week ending  ${repend_date}" -S smtp=smtp://mailhub.intra.tdaf.com:25 vs@xx123.com
fi

chmod 777 /tmp/dcdcloudreportnew.pdf
rm -f dcdcloudmessageout dcdcloudsyslogdeviceout dcdcloudcompsys.txt  dcdcloudreportnew$repend_date.pdf dcdcloudjsonoutput dcdcloudcompsys.ps
EOF
chmod 755 dcdcloudtemppdf.sh
cd /root/logstash-pdfreports
./dcdcloudtemppdf.sh

