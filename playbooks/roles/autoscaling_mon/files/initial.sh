wget https://dl.grafana.com/oss/release/grafana-7.5.0-1.x86_64.rpm
sudo yum install -y grafana-7.5.0-1.x86_64.rpm
sudo yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm
sudo yum install -y mysql-shell
sudo pip3 install protobuf==3.19.4
sudo pip3 install mysql-connector-python==8.0.31
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl status grafana-server
sudo systemctl enable grafana-server
echo OK >> /opt/oci-hpc/monitoring/activated