#!/bin/bash
#Создание резервной копии виртуальной машины

# Параметры бэкапа:
TIMESTAMP=$( date +%d.%m.%Y_%H:%M )			# Создание временной метки
DUMP_NUM=7									# Число бэкапов
FOLDER_Backup="/mnt/md0/backup-vm"			# Расположение бэкапов
BACKUP_VM=$1								# Имя виртуальной машины

# Проверка наличия параметра запуска
if [ -z "$1" ]
  then
      echo " "  
      echo "Do not Set option. Run the script is not possible!"
      echo "Example:"
      echo "         sudo sh ./kvm_backup_vm.sh VM"
      echo " "  
	  exit 1
  else
	  # Проверка существования виртуальной машины
	  if virsh dumpxml $BACKUP_VM > /dev/null 2>&1 ; then
			echo "$BACKUP_VM is exist"
		else
			echo "$BACKUP_VM not found!"
			exit 1
	  fi
fi

#virsh dumpxml lse1d > /dev/null 2>&1
#if [ $? -eq 0 ]; then
#    echo OK
#else
#    echo FAIL
#fi


echo "Выполняется архивирование виртуальной машины $BACKUP_VM"
echo "......................................................."
# Если каталога для бэкапа нет, то создаем
[ -d $FOLDER_Backup ] || sudo mkdir $FOLDER_Backup

# Если каталога для бэкапа машины нет, то создаем
[ -d $FOLDER_Backup/$BACKUP_VM ] || sudo mkdir $FOLDER_Backup/$BACKUP_VM

DISK=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $1}'`			# Тип диска (vda или hda)
DISK_PATH=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $2}'`		# Путь (VM_STORAGE/win2k12r2.qcow2)
DISK_SNAPSHOT=$BACKUP_VM-snapshot.qcow2

FILE=`basename $DISK_PATH`
filename="${FILE%.*}"
extension="${FILE##*.}"
ARHIV="${filename}.(${TIMESTAMP}).${extension}.gz"
ARHIV_CFG="${BACKUP_VM}.(${TIMESTAMP}).xml"

#------------------------------------------
# 2 - Создание снапшота
#------------------------------------------

echo "create snapshot $BACKUP_VM to $FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT"
virsh snapshot-create-as --domain $BACKUP_VM backup-snapshot -diskspec $DISK,file=$FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT --disk-only --atomic --quiesce --no-metadata

#------------------------------------------
# 3 - Создание резервной копии машины
#------------------------------------------

echo "Backup VM disk to $FOLDER_Backup/$BACKUP_VM/$ARHIV"
pigz -c $DISK_PATH > $FOLDER_Backup/$BACKUP_VM/$ARHIV

#------------------------------------------
# 4 - Объединение снапшота с рабочим диском
#------------------------------------------

#Когда выполнение бэкапа завершено, объединим снапшот с основным файлом:
virsh blockcommit $BACKUP_VM $DISK --active --verbose --pivot

#После этого файл снэпшота можно удалить:
rm $FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT

#------------------------------------------
# 5 - Создание резервной копии конфигурации
#------------------------------------------

#Для полноты картины забэкапим еще и настройки виртуалки:
echo "Backup VM settings to $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG"
virsh dumpxml $BACKUP_VM > $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG

echo "Архивирование виртуальной машины $BACKUP_VM завершено!"
echo "......................................................"

#------------------------------------------
# 6 - Удаление бэкапов старше DUMP_NUM дней
#------------------------------------------

  # выполняется поиск всех файлов старше DUMP_NUM дней 
  # в каталоге $FOLDER_Backup и их удаление
  if [ "$SUCCESS" = 1 ]; then
	sudo find $FOLDER_Backup -type f -mtime +$DUMP_NUM -exec rm {} \;
  fi

echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # The script is completed."
