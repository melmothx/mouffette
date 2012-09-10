#!/bin/bash

cat /proc/`cat bot.pid`/status | grep -i vmsize
