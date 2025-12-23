#!/bin/bash
# Live monitoring dashboard for rollout

watch -n 30 -t '/root/Breezeway/scripts/check_rollout_status.sh'
