#!/bin/bash
#Создание резервной копии виртуальной машины KVM

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

#virsh dumpxml lsed > /dev/null 2>&1
#if [ $? -eq 0 ]; then
#    echo OK
#else
#    echo FAIL
#fi

echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # Start script."
echo "......................................................."
echo "Выполняется архивирование виртуальной машины $BACKUP_VM"
echo "......................................................."
#------------------------------------------
# 0 - Проверка каталогов
#------------------------------------------
# Если каталога для бэкапа нет, то создаем
[ -d $FOLDER_Backup ] || sudo mkdir $FOLDER_Backup

# Если каталога для бэкапа машины нет, то создаем
[ -d $FOLDER_Backup/$BACKUP_VM ] || sudo mkdir $FOLDER_Backup/$BACKUP_VM

#------------------------------------------
# 1 - Инициализация
#------------------------------------------

DISK=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $1}'`			# Тип диска (vda или hda)
DISK_PATH=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $2}'`		# Путь (VM_STORAGE/win2k12.qcow2)
DISK_SNAPSHOT=$BACKUP_VM-snapshot.qcow2

FILE=`basename $DISK_PATH`
filename="${FILE%.*}"
extension="${FILE##*.}"
ARHIV="${filename}.(${TIMESTAMP}).${extension}.gz"
ARHIV_CFG="${BACKUP_VM}.(${TIMESTAMP}).xml"
ARHIV_CFG_BEFORE="${BACKUP_VM}.(${TIMESTAMP})_Before.xml"					# Резервация конфига на случай сбоя архивирования

#------------------------------------------
# 2 - Создание снапшота
#------------------------------------------

echo "......................................................."
echo "Reserved config VM to $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE"
virsh dumpxml $BACKUP_VM > $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE
echo "......................................................."
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # Start snapshot."  
echo "Create snapshot to $FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT"
virsh snapshot-create-as --domain $BACKUP_VM backup-snapshot -diskspec $DISK,file=$FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT --disk-only --atomic --quiesce --no-metadata
if [ $? -eq 0 ]; then
    echo "Snapshot is created"
else
    echo "Error creating snapshot!"
	exit 1
fi
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # End snapshot."  

#------------------------------------------
# 3 - Создание резервной копии машины
#------------------------------------------

echo "......................................................."
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # Start backup."  
echo "Backup VM disk to $FOLDER_Backup/$BACKUP_VM/$ARHIV"
pigz -c $DISK_PATH > $FOLDER_Backup/$BACKUP_VM/$ARHIV
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # End backup."  

#------------------------------------------
# 4 - Объединение снапшота с рабочим диском
#------------------------------------------

echo "......................................................."
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # Start merge."  
#Когда выполнение бэкапа завершено, объединим снапшот с основным файлом:
virsh blockcommit $BACKUP_VM $DISK --active --verbose --pivot
if [ $? -eq 0 ]; then
    echo "Merge OK"
	rm $FOLDER_Backup/$BACKUP_VM/$DISK_SNAPSHOT
else
    echo "Merge Error!"
	exit 1
fi
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # End merge."  

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
