#!/bin/bash
#Создание резервной копии виртуальной машины KVM

# Параметры бэкапа:
TIMESTAMP=$( date +%d.%m.%Y_%H.%M )			# Создание временной метки
DUMP_NUM=21									# Число дней хранения бэкапов
FOLDER_Backup="/mnt/md0/backup-vm"			# Расположение бэкапов
BACKUP_VM=$1								# Имя виртуальной машины
SNAPSHOT=false								# По умолчанию снапшота быть не должно 

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
			echo "Log: Виртуальная машина $BACKUP_VM - найдена."
		else
			echo "Log: Виртуальная машина $BACKUP_VM не существует!"
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
TYPE="tar.gz"
#ARHIV="${filename}_${TIMESTAMP}_${extension}.${TYPE}"
ARHIV="${filename}_${TIMESTAMP}.${TYPE}"
ARHIV_CFG="${BACKUP_VM}_${TIMESTAMP}.xml"
ARHIV_CFG_BEFORE="${BACKUP_VM}_${TIMESTAMP}_Before.xml"					# Резервация конфига на случай сбоя архивирования
ARHIV_PATH="$FOLDER_Backup/$BACKUP_VM/$ARHIV"

VM_STATE=`virsh domstate $BACKUP_VM` 


#------------------------------------------
# --- Функиции
#------------------------------------------

# Функция - Проверка наличия снапшота
snapshot_check()
{
  # Проверка наличия снимка
  if [ -f "$SNAPSHOT_PATH" ]; then
    echo "Log: Найден снапшот. Выболняется объединение." 
	SNAPSHOT=true	
	snapshot_merge
  fi
}

# Функция - Создание снапшота
snapshot_create()
{
  echo "......................................................."
  echo "Создание снапшота в $SNAPSHOT_PATH"
  virsh snapshot-create-as --domain $BACKUP_VM backup-snapshot -diskspec $DISK,file=$SNAPSHOT_PATH --disk-only --atomic --quiesce --no-metadata
  if [ $? -eq 0 ]; then
      echo "Log: снапшот создан."
  else
      echo "Log: ошибка создания снапшота!"
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
	  echo "Log: Снапшот будет удален!"
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

snapshot_check
echo "......................................................."
echo "Log: Сделана резервная копия настроек машины в файл $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE"
virsh dumpxml $BACKUP_VM > $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG_BEFORE

#if [ $(virsh domstate $BACKUP_VM | grep -c "shut off") -eq 0 ]; then
#if [ $(virsh domstate $BACKUP_VM | grep -cE "(shut off|paused)") -eq 0 ]; then
if [ $(echo $VM_STATE | grep -cE "(shut off|paused)") -eq 0 ]; then
   snapshot_create
else
	echo "Log: Машина в состоянии $VM_STATE. Создание снимка не требуется"   
fi

#------------------------------------------
# 2 - Создание резервной копии машины
#------------------------------------------

ARHIV_FULL_PATH=""
DISK_FULL_PATH=""

if	$SNAPSHOT; then
	DISK_PATH2=`virsh domblklist $BACKUP_VM | grep qcow2 | awk '{print $2}'`
	FILE2=`basename $DISK_PATH2`
	ARHIV_PATH2="$FOLDER_Backup/$BACKUP_VM/${FILE2%.*}_${TIMESTAMP}.tar.gz"	
	ARHIV_FULL_PATH=$ARHIV_PATH2
	DISK_FULL_PATH=$DISK_PATH2
else
	ARHIV_FULL_PATH=$ARHIV_PATH
	DISK_FULL_PATH=$DISK_PATH
fi 


echo "......................................................."
echo "Создание резервной копии диска $DISK_FULL_PATH в $ARHIV_FULL_PATH"
#tar czvfP $ARHIV_FULL_PATH $DISK_FULL_PATH
tar czfP $ARHIV_FULL_PATH $DISK_FULL_PATH
#pigz -c $DISK_FULL_PATH > $ARHIV_FULL_PATH

if [ -f "$ARHIV_FULL_PATH" ]; then
	echo "Log: Резервное копирвоание успешно завершено!"    
	SUCCESS=1
else
	echo "Log: Произошла ошибка при выполнении резервного копирования!!"
	exit 1;
fi  

#------------------------------------------
# 3 - Объединение снапшота с рабочим диском
#------------------------------------------

snapshot_check

#------------------------------------------
# 4 - Создание резервной копии конфигурации
#------------------------------------------

echo "......................................................."
echo "Log: Сделана резервная копия настроек машины в файл $FOLDER_Backup/$BACKUP_VM/$ARHIV_CFG"
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
echo "Для распаковки в каталог, выполните команду, например:"
echo "tar -C /mnt/md0/backup-vm/ -xzf $ARHIV_FULL_PATH"
echo "......................................................."
