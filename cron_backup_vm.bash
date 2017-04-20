# Ежедневный бэкап VM
# Предварительно выполнить команду: chmod +x kvm_backup_vm.sh
00 01 * * * root /root/kvm_backup_vm.sh DV_5.4_KRD_Test >> /mnt/md0/logs/log_backup_vm.log
