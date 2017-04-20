#!/bin/bash
#Создание резервной копии виртуальной машины KVM

# Параметры бэкапа:
TIMESTAMP=$( date +%d.%m.%Y_%H:%M )			# Создание временной метки
DUMP_NUM=7									# Число бэкапов
FOLDER_Backup="/mnt/md0/backup-vm"			# Расположение бэкапов
BACKUP_VM=$1								# Имя виртуальной машины

#------------------------------------------
# --- Проверка наличия параметра запуска
#------------------------------------------

echo " "
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
			echo "Log: $BACKUP_VM is exist"
		else
			echo "Log: $BACKUP_VM not found!"
			exit 1
	  fi
fi

#------------------------------------------
# --- Проверка каталогов
#------------------------------------------

# Если каталога для бэкапа нет, то создаем
[ -d $FOLDER_Backup ] || sudo mkdir $FOLDER_Backup

# Если каталога для бэкапа машины нет, то создаем
[ -d $FOLDER_Backup/$BACKUP_VM ] || sudo mkdir $FOLDER_Backup/$BACKUP_VM

#------------------------------------------
# --- Инициализация
#------------------------------------------

DISK=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $1}'`			# Тип диска (vda или hda)
DISK_PATH=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $2}'`		# Путь (VM_STORAGE/win2k12.qcow2)
SNAPSHOT_FILE="$BACKUP_VM-snapshot.qcow2"
SNAPSHOT_PATH="$FOLDER_Backup/$BACKUP_VM/$SNAPSHOT_FILE"

FILE=`basename $DISK_PATH`
filename="${FILE%.*}"
extension="${FILE##*.}"
ARHIV="${filename}.(${TIMESTAMP}).${extension}.gz"
ARHIV_CFG="${BACKUP_VM}.(${TIMESTAMP}).xml"
ARHIV_CFG_BEFORE="${BACKUP_VM}.(${TIMESTAMP})_Before.xml"					# Резервация конфига на случай сбоя архивирования
ARHIV_PATH="$FOLDER_Backup/$BACKUP_VM/$ARHIV"

VM_STATE=`virsh domstate $BACKUP_VM` 

#------------------------------------------
# --- Функиции
#------------------------------------------

# Функция - Создание снапшота
snapshot_create()
{
  echo "......................................................."
  echo "Create snapshot to $SNAPSHOT_PATH"
  virsh snapshot-create-as --domain $BACKUP_VM backup-snapshot -diskspec $DISK,file=$SNAPSHOT_PATH --disk-only --atomic --quiesce --no-metadata
  if [ $? -eq 0 ]; then
      echo "Log: Snapshot is created"
  else
      echo "Log: Error creating snapshot!"
	  exit 1
  fi
}

# Функция - Объединение снапшота и основного диска
snapshot_merge()
{
  echo "......................................................."
  virsh blockcommit $BACKUP_VM $DISK --active --verbose --pivot
  if [ $? -eq 0 ]; then
      echo "Log: Merge OK"
	  echo "Log: The snapshot will be deleted!"
	  rm $SNAPSHOT_PATH
  else
      echo "Log: Merge Error!"
	  exit 1
  fi
}

echo "======================================================="
echo "Выполняется архивирование виртуальной машины $BACKUP_VM"
echo "======================================================="
echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # Start script."

#------------------------------------------
# 1 - Создание снапшота
#------------------------------------------

echo "......................................................."
echo "Reserved config VM to $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE"
virsh dumpxml $BACKUP_VM > $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE

#if [ $(virsh domstate $BACKUP_VM | grep -c "shut off") -eq 0 ]; then
#if [ $(virsh domstate $BACKUP_VM | grep -cE "(shut off|paused)") -eq 0 ]; then
if [ $(echo $VM_STATE | grep -cE "(shut off|paused)") -eq 0 ]; then
   snapshot_create
else
	echo "Машина в состоянии $VM_STATE. Создание снимка не требуется"   
fi

#------------------------------------------
# 2 - Создание резервной копии машины
#------------------------------------------

echo "......................................................."
echo "Backup VM disk to $ARHIV_PATH"
pigz -c $DISK_PATH > $ARHIV_PATH
  # Проверка наличия созданного бэкапа
  if [ -f "$ARHIV_PATH" ]; then
    echo "Backup SUCCESSFUL!"    
    SUCCESS=1
  else
    echo "Backup Error!!"
	exit 1;
  fi

#------------------------------------------
# 3 - Объединение снапшота с рабочим диском
#------------------------------------------

  # Проверка наличия снимка
  if [ -f "$SNAPSHOT_PATH" ]; then
	snapshot_merge
  fi

#------------------------------------------
# 4 - Создание резервной копии конфигурации
#------------------------------------------

echo "......................................................."
echo "Backup VM settings to $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG"
virsh dumpxml $BACKUP_VM > $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG
echo "......................................................"

#------------------------------------------
# 5 - Удаление бэкапов старше DUMP_NUM дней
#------------------------------------------

  # выполняется поиск всех файлов старше DUMP_NUM дней 
  # в каталоге $FOLDER_Backup и их удаление
  if [ "$SUCCESS" = 1 ]; then
	sudo find $FOLDER_Backup -type f -mtime +$DUMP_NUM -exec rm {} \;
  fi

echo "$(date +%d.%m.%Y) ($(date +%H.%M:%S)) # The script is completed."
