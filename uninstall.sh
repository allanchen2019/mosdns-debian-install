#!/bin/bash

clear
cd /opt/mosdns-cn
./mosdns-cn --service stop
./mosdns-cn --service uninstall
rm -rf /opt/mosdns-cn
