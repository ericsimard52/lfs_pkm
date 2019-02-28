#!/bin/bash

declare CONFIGFILE="/etc/pkm/pkm.conf"
declare SD TD SDN SDNCONF PKG EXT HASBUILDDIR BUILDDIR CONFBASE BYPASSIMPLEMENT WGETURL FAKEROOT
declare UNPACKCMD
declare MAKEFLAGS
declare DEBUG=0
declare LOGFILE
declare LOGFILEFD
declare ISIMPLEMENTED=1 # This changes to 0 when implementation is done.
declare CURSTATE=0 # Set to 1 to exit program succesfully


# Config files
declare GENCONFIGFILE DEPCHECKCMDFILE PRECONFIGCMDFILE CONFIGCMDFILE COMPILECMDFILE CHECKCMDFILE
declare PREINSTALLCMDFILE INSTALLCMDFILE PREIMPLEMENTCMDFILE POSTIMPLEMENTCMDFILE
declare -a CMDFILELIST AUTOINSTALLCMDLIST

function singleton {
    if [ ! -d /var/run/pkm ]; then
        echo "Creating /var/run/pkm"
        install -vdm 644 /var/run/pkm
    fi
    if [ ! -d /var/log/pkm ]; then
        echo "Creating /var/log/pkm"
        install -vdm 644 /var/log/pkm
    fi
    if [ ! -d /var/log/pkm/implementationLog ]; then
        echo "Creating /var/log/pkm"
        install -vdm 644 /var/log/pkm
    fi
    if [ -f /var/run/pkm/pkm.lock ]; then
        quitPkm 1 "Pkm is already running or has not quit properly, in that case, remove /var/run/pkm/pkm.lock" t
    fi
    touch /var/run/pkm/pkm.lock
    [ $? -gt 0 ] && quitPkm 1 "Unable to create lock file."
    if [ -f /usr/bin/pkmFirstRun.sh ]; then
        echo "pkmFirstRun is present, running."
        /usr/bin/pkmFirstRun.sh
        [ $? -gt 0 ] && quitPkm 1 "Error with pkmFirstRun."
        rm -v /usr/bin/pkmFirstRun.sh
        [ $? -gt 0 ] && quitPkm 1 "Error removing /usr/bin/pkmFirstRun.sh do it manually."
        quitPkm 0 "pkmFirstRun returned 0, restart pkm"
    fi
}

function startLog {
    if [ ! -f $LOGFILE ]; then
        log "NULL|INFO|Creating $LOGFILE" t
         touch $LOGFILE
         chmod 666 -v $LOGFILE
    fi
    log "NULL|INFO|Creating file descriptor for logs" t t
    exec {LOGFILEFD}>$LOGFILE
}

function quitPkm {
    ## First log exit message if present
    if [ -n "$2" ]; then
        log "GEN|WARNING|Exist Message received: $2"
    fi
    declare ret=0 ## Default exit value
    if [ $1 ]; then ret=$1; fi ## Override exit value

    [ $? -gt 0 ] && echo "ERROR with unMountLfs, CHECK YOUR SYSTEM." && ret=1

    log "GEN|INFO|Closing logs." t
    [ ${LOGFILEFD} ] && exec {LOGFILEFD}>&-

    unset LOGFILE
    unset LOGFILEFD

    if [ -f /var/run/pkm/pkm.lock ]; then
        log "GEN|INFO|Removing pkm lock." t
         rm /var/run/pkm/pkm.lock
        [ $? -gt 0 ] && echo "Error removing lock." && exit $res
    fi
    if [[ ! "$2" = "" ]]; then
        echo "Quitting message: $2."
    fi

    exit $ret
}

function dumpEnv {
printf "\e[1mEnvironment Var:\e[0m
\e[34mDEBUG: \e[32m$DEBUG
\e[34mSD: \e[32m$SD
\e[34mSDN: \e[32m$SDN
\e[34mTF: \e[32m$TF
\e[34mSDNCONF: \e[32m$SDNCONF
\e[34mEXT: \e[32m$EXT
\e[34mHASBUILDDIR: \e[32m$HASBUILDDIR
\e[34mMAKEFLAGS: \e[32m$MAKEFLAGS
\e[34mBUILDDIR: \e[32m$BUILDDIR
\e[34mLFS: \e[32m$LFS
\e[34mCONFIGFILE: \e[32m$CONFIGFILE
\e[34mCONFBASE: \e[32m$CONFBASE
\e[34mGENLOG: \e[32m$GENLOGFILE
\e[34mGENLOGFD: \e[32m$GENLOGFD
\e[34mPKGLOG: \e[32m$PKGLOGFILE
\e[34mPKGLOGFD: \e[32m$PKGLOGFD
\e[34mIMPLOG: \e[32m$IMPLOGFILE
\e[34mIMPLOGFD: \e[32m$IMPLOGFD
\e[34mERRLOG: \e[32m$ERRLOGFILE
\e[34mERRLOGFD: \e[32m$ERRLOGFD\e[0m\n"
}

function readConfig {
    log "NULL|INFO|Reading configuration file." t
    if [ ! -f $CONFIGFILE ]; then
        quitPkm 1 "NULL|ERROR|Configuration file: /etc/pkm/pkm.conf is missing. Do you need to run installManager?"
    fi
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            debug)
                DEBUG=${PARAM[1]}
                if [[ $DEBUG > 0 ]];then
                    log "NULL|INFO|Set param DEBUG:$DEBUG" t
                fi
                ;;
            sd)
                SD=${PARAM[1]}
                log "NULL|INFO|Set param sd:$SD" t t
                ;;
            confBase)
                CONFBASE=${PARAM[1]}
                log "NULL|INFO|Set param confBase:$CONFBASE" t t
                ;;
            MAKEFLAGS)
                MAKEFLAGS=${PARAM[1]}
                log "NULL|INFO|Set param MAKEFLAGS:$MAKEFLAGS" t t
                ;;
            FAKEROOT)
                FAKEROOT=${PARAM[1]}
                log "NULL|INFO|Set param FAKEROOT:$FAKEROOT" t t
                ;;
            bypassImplement)
                BYPASSIMPLEMENT=${PARAM[1]}
                log "NULL|INFO|Set param bypassImplement:$BYPASSIMPLEMENT" t t
                ;;
            logFile)
                LOGFILE=${PARAM[1]}
                log "NULL|INFO|Set param LOGFILE:$LOGFILE" t t
                ;;
            "#") continue;;
            *) continue;;
        esac
        unset IFS
    done < $CONFIGFILE
    export MAKEFLAGS
    log "NULL|INFO|Done reading config file." t
}

function processCmd {
    local cmd=""
    for part in $@; do
        cmd=$cmd" "$part
    done
    log "GEN|INFO|Processing cmd: $cmd"
    eval "tput sgr0"
    if [[ $DEBUG < 1 ]]; then
        $cmd >&${LOGFILEFD} 2>&1
    elif [[ $DEBUG > 0 ]]; then
        $cmd | tee >&${LOGFILEFD} 2>&1
    fi
    if [ $? -gt 0 ]; then
       log "GEN|ERROR|Error processcing cmd $cmd" t
       return 1
    fi
    return
}

function log {
    ## Format
    ## log "LEVEL|..." PRINTOSTDOUT DEBUGONLYMESSAGE
    ## log "INFO|..." t = print to stdout
    ## log "INFO|..." t t = print to stdout only if debug=1
    ## log "INFO|..." - t = process only if debug=1 and send only to LOGFILE
    ## Messages are always sent to LOGFILE

    if [ $3 ] && [[ $DEBUG = 0 ]]; then # if 3 param set, we process msg only if debug is 1
        return
    fi
    declare _LEVEL _COLOR _MSG _M _LOGMSG _CALLER _CALLERLOG

    MSGEND=" \e[0m" ## Clear all formatting

    ## Setting up file descriptor destination
    IFS='|' read -ra PARTS <<< $1
    ### Set color formatting
    case "${PARTS[1]}" in
        INFO)
            _LEVEL=INFO
            _COLOR="\e[35m"
            ;;
        WARNING)
            _LEVEL=WARNING
            _COLOR="\e[33m"
            ;;
        ERROR)
            _LEVEL=ERROR
            _COLOR="\e[31m"
            ;;
        FATAL)
            _LEVEL=FATAL
            _COLOR="\e[31m"
            ;;
    esac

    ### Append message provided by caller
    _M="${PARTS[2]}"
    if [[ "$_M" = "" ]]; then
        log "NULL|ERROR|Empty log message?!?!" t
    fi

    if [ $SDN ]; then
        _CALLER="\e[32m"$PKG"\e[0m "
        _CALLERLOG=$PKG
    else
        _CALLERLOG="NONE"
        _CALLER="\e[32mNONE\e[0m "
    fi
    _MSG=$_COLOR$_LEVEL" - "$_CALLER":"$_COLOR$_M$_MSGEND ## Full message string
    _LOGMSG=$_LEVEL" - "$_CALLERLOG":"$_M$_MSGEND

    # Printo stdOut
    [ ${LOGFILEFD} ] && echo $_LOGMSG >&${LOGFILEFD}
    if [[ $2 ]] && [[ "$2" = "t" ]]; then # if t after message, print to stdout
        echo -e $_MSG
    fi


    unset IFS _FDs _LEVEL _COLOR _MSG _M _MSGEND _LOGMSG _CALLER _CALLERLOG
    return
}

function promptUser {
    COLOR="\e[37m"
    echo -en $COLOR$1" : \e[0m"
}

function checkInstalled {
    processCmd "command -v $1"
    if [[ $? > 0 ]]; then
        processCmd "locate $1"
        [ $? -gt 0 ] && return 1
    fi
    return 0
}

function checkLibInstalled {
    ldconfig -p | grep $1
    [ $? -gt 0 ] && return 1
    return 0
}

function checkVersion {
    quitPkm 1 "Change to use getVersion. Do not use this function."
    reqCmd=$1
    reqVer=$2
    cmdVersion=`$1 --version |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
    if [[ $? > 0 ]]; then
        log "PKG|WARNING|Unable to fetch version, attempting another way." t t
        cmdVersion=`$1 -version |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
        log "PKG|ERROR|Could not find version for $1." t
        return 1
    fi
    log "PKG|INFO|Found version: $cmdVersion." t t
    vercomp $cmdVersion $reqVer
    return $?
}

function getVersion {
    reqCmd="$1"
    log "GEN|INFO|Getting version of "$reqCmd t
    cmdVersion=`timeout 5 $1 --version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
    if [[ $? > 0 ]]; then
        log "PKG|WARNING|Unable to fetch version, attempting another way." t
        cmdVersion=`$1 -version 2>&1  | sed '/^$/d' |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
        if [[ $? > 0 ]]; then
            log "PKG|ERROR|Could not find version for $1." t
            return 1
        fi
    fi
    log "PKG|INFO|Found version: $cmdVersion." t
    log "GEN|INFO|Removing all non numeric character." t
    cmdVersion=$(echo $cmdVersion | sed 's/[^0-9]*//g')
    log "GEN|INFO|cmdVersion: $cmdVersion." t
    eval "$2=$cmdVersion"
    [ $? -gt 0 ] && return 1 || return 0
}

function vercomp {
    declare cp='>='; ## Default comparator if not provided
    if [[ $3 ]]; then
        cp=$3
    fi
    log  "GEN|INFO|Comparing version: $1 $cp $2" t
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i installedVer=($1) neededVer=($2) iv nv
    ivCount=0
    nvCount=0
    nvPad=0
    ivPad=0
    for (( i=0; i<${#installedVer[@]}; i++ )); do
        iv=$iv${installedVer[$i]}
    done

    for (( i=0; i<${#neededVer[@]}; i++ )); do
        nv=$nv${neededVer[$i]}
    done
    iv=$(echo $iv | sed 's/[^0-9]*//g')
    nv=$(echo $nv | sed 's/[^0-9]*//g')
    log "GEN|INFO|Getting count for iv: $iv" - t
    ivCount=${#iv}
    log "GEN|INFO|Getting count for mv: $nv" - t
    nvCount=${#nv}
    log "GEN|INFO|nv: $nv" - t
    log "GEN|INFO|iv: $iv" - t
    log "GEN|INFO|ivCount: $ivCount" - t
    log "GEN|INFO|nvCount: $nvCount" - t
    if [ $ivCount -lt $nvCount ]; then
        ivPad=$(( $nvCount - $ivCount ))
        log "GEN|INFO|ivPad: $ivPad" - t
    elif [ $nvCount -lt $ivCount ]; then
        nvPad=$(( $ivCount - $nvCount ))
        log "GEN|INFO|nvPad: $nvPad" - t
    else
        log "GEN|INFO|No padding needed" - t
    fi
    for (( i=0; i<$nvPad; i++ )); do
        nv=$nv"0"
    done
    for (( i=0; i<$ivPad; i++ )); do
        iv=$iv"0"
    done

    log "GEN|INFO|iv: $iv nv: $nv" - t
    unset ivCount nvCount nvPad ivPad i
    case "$cp" in
        ">")
            [ $iv -gt $nv ] && return 0 || return 1
            ;;
        "<")
            [ $iv -lt $nv ] && return 0 || return 1
            ;;
        "="|"==")
            [ $iv -eq $nv ] && return 0 || return 1
            ;;
        ">=")
            if (( $iv >= $nv )); then
                return 0
            fi
            ;;
        "<=")
            if (( $iv <= $nv )); then
                return 0
            fi
            ;;
        *)
            log "{GEN,ERR}|ERROR|Unknown comparator in checkVersion." t
            return 1
            ;;
    esac

    return 1
}

function loadPkg {
    if [[ $PKG ]]; then
        log "GEN|INFO|Unloading $PKG from memory." t
        unloadPkg
    fi

    if [ $1 ]; then
        PKG=$1
    else
        promptUser "Which package?"
        read PKG
    fi
    if [[ "$PKG" == "" ]]; then
        log "ERR|INFO|Empty package provided..."
        return 1
    fi
    if [ ! -d $CONFBASE/$PKG ]; then
        declare -a foundFiles
        for file in `find $CONFBASE -maxdepth 1 -type d -iname "$PKG*"`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "GEN|INFO|Using: $file" t
                    PKG=$(basename $file)
                    if [ ! -d $CONFBASE/$PKG ]; then
                        log "ERR|FATAL|Could not find $PKG after finding it????" t
                        return 1
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -d $CONFBASE/$PKG ]; then
            log "ERR|FATAL|No package found for $PKG." t
            return 1
        fi
    fi
    SDNCONF=$CONFBASE/$PKG
    log "PKG|INFO|SDNCONF set: $SDNCONF." t
    GENCONFIGFILE="$SDNCONF/$PKG.conf"
    log "PKG|INFO|genConfigFile set: $GENCONFIGFILE." t
    if [ ! -f $GENCONFIGFILE ]; then
        log "ERR|ERROR|Package general config file missing" t
        return 1
    fi

    log "PKG|INFO|Reading config file into variables" t
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf)
                log "PKG|INFO|tf: ${PARAM[1]}" t
                TF=${PARAM[1]}
                ;;
            sdn)
                log "PKG|INFO|sdn: ${PARAM[1]}" t
                SDN=${PARAM[1]}
                ;;
            sd)
                log "PKG|INFO|sd: ${PARAM[1]}" t
                SD=${PARAM[1]}
                ;;
            hasBuildDir)
                log "PKG|INFO|hasBuildDir: ${PARAM[1]}" t
                HASBUILDDIR=${PARAM[1]}
                ;;
            bypassImplement)
                log "PKG|INFO|bypassImplement: ${PARAM[1]}" t
                BYPASSIMPLEMENT=${PARAM[1]}
                ;;
            tasks)
                log "PKG|INFO|Loading tasks list." t
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    log "PKG|INFO|Adding ${TASK[$x]}." t
                    AUTOINSTALLCMDLIST+=(${TASK[$x]})
                    ((x++))
                done
                IFS=':'
                ;;
            makeflags)
                log "PKG|INFO|Chaning makeflags" t
                MAKEFLAGS=${PARAM[1]}
                ;;
            DEBUG) DEBUG=${PARAM[1]};;
            *) log "{GEN,ERR}|ERROR|Unknow params: ${PARAMS[1]}" t;;
        esac
        unset IFS
    done < $GENCONFIGFILE


    log "GEN|INFO|Check if source package exists: $SD/$tf" t
    # Check if source package exists
    ## What is this
    if [ ! -f $SD/$TF ]; then
        log "PKG|WARNING|Why are we doing this?" t
        log "{GEN,ERR}|WARNING|Package $tf not found in source $SD, creating." t
        processCmd " install -vm664 $DEVBASE/sources/$TF $SD/$TF"
        return
    fi

    EXT="${TF##*.}"
    log "PKG|INFO|Extension established: $EXT" t
    log "PKG|INFO|Calling setCmdFileList." t
    setCmdFileList
    if [ $HASBUILDDIR -lt 1 ]; then
        BUILDDIR=$SD/$SDN/build
        log "GEN|INFO|Checking if build dir: $BUILDDIR exists." t
        if [ ! -d "$BUILDIR" ]; then
            log "GEN|WARNING|Build directory flag set, but dir does not exist, creating..." t
            processCmd "install -vdm755 $BUILDDIR"
            [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating $BUILDDIR." t && return 1
        fi
    else
        BUILDDIR=$SD/$SDN
    fi
    log "PKG|INFO|buildDir set: $BUILDDIR." t

    # Adjusting the unpack commands
    log "GEN|INFO|Adjusting unpack command for $EXT." t
    if [[ "$EXT" == "xz" ]]; then
        UNPACKCMD="tar xvf $TF"
    elif [[ "$EXT" == "gz" ]]; then
        UNPACKCMD="tar xvfz $TF"
    elif [[ "$EXT" == "gzip" ]]; then
        UNPACKCMD="tar xvfz $TF"
    elif [[ "$EXT" == "bz2" ]]; then
        UNPACKCMD="tar xvfj $TF"
    elif [[ "$EXT" == "tgz" ]]; then
        UNPACKCMD="tar xvfz $TF"
    else
        log "ERR|FATAL|Unknown package unpack method." true
        return 0
    fi
    log "PKG|INFO|unpackCmd set: $UNPACKCMD." t
    return 0
}

function unloadPkg {
    unset -v PKG SDNCONF TF SDN HASBUILDDIR BUILDDIR LD EXT UNPACKCMD BANNER GENCONFIGFILE DEPCHECKCMDFILE PRECONFIGCMDFILE CONFIGCMDFILE COMPILECMDFILE CHECKCMDFILE PREINSTALLCMDFILE INSTALLCMDFILE PREIMPLEMENTCMDFILE POSTIMPLEMENTCMDFILE CMDFILELIST PRECONFIGCMD CONFIGCMD COMPILECMD CHECKCMD PREINSTALLCMD INSTALLCMD PREIMPLEMENTCMD POSTIMPLEMENTCMD AUTOINSTALLCMDLIST
    ISIMPLEMENTED=1
}

function unpack {
    log "{GEN,PKG}|INFO|Unpacking source code $TF" t

    if [ ! -f $SD/$TF ]; then
        log "{GEN,PKG,ERR}|FATAL|$TF not found." t
        return 1
    fi

    log "PKG|INFO|Running Cmd: $UNPACKCMD" t t
    mPush $SD
    processCmd "${UNPACKCMD}"
    [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error unpacking with $UNPACKCMD" t && mPop &&  return 1
    if [ $HASBUILDDIR == 0 ] && [ ! -d $SD/$SDN/build ]; then
        log "PKG|INFO|Creating build directory" t
        processCmd "install -oroot -groot -vdm755 $SD/$SDN/build"
        [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error creating build directory" t && mPop && return 1
    fi

    log "{GEN,PKG}|INFO|Done." t
    mPop
    return 0
}

function autoInstall {
    log "GEN|INFO|AutoInstall will be running the following tasks:"
    i=0
    while [[ $i < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        echo "${AUTOINSTALLCMDLIST[$i]}"
        ((i++))
    done
    promptUser "Do you wanto start now?"
    read y
    case $y in
        [nN])
            return 0
            ;;
        [yY]|*)
            runAutoInstall
            [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Error during autoInstall." t && return 1
            ;;
    esac
    return 0
}

function runAutoInstall {
    ii=0
    log "PKG|INFO|Starting auto install." t
    while [[ $ii < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        f=${AUTOINSTALLCMDLIST[$ii]}
        ((ii++))
        log "GEN|INFO|Sourcing $f." true
        evalPrompt $f
        [ $? -gt 0 ] && log "{PKG,ERR}|ERROR|Error sourcing $f. Aborting!" t && return 1
    done
    log "PKG|INFO|Auto install completed, all seems to be good." t
    return 0
}

function searchPkg {
    # If we can't file the package (source tar), we do a search for the term provided by the user.
    declare -a foundFiles
    for file in `find $SD -maxdepth 1 -type f -iname "$1*"`; do
        promptUser "FoundFiles: $file\n Use it? Y/n"
        read u
        case $u in
            [nN])
                continue
                ;;
            [yY]|*)
                log "GEN|INFO|Using: $file" t
                PKG=$(basename $file)
                log "{GEN,PKG}|INFO|pkg seto $PKG" t
                if [ ! -f $SD/$PKG ]; then
                    log "{GEN,ERR}|FATAL|Could not find $PKG after finding it????" t
                    return 1
                fi
                break
                ;;
        esac
    done
    if [ ! -f $SD/$PKG ]; then
        log "GEN|WARNING|No package found for $PKG*." t
        return 1
    fi
}

function sourceScript {
    c=$1
    log "GEN|INFO|Sourcing: $c" t
    source $c
    [ $? -gt 0 ] && log "{GEN,ERR}|ERROR|Failed." t && return 1
    log "GEN|INFO|Success." t
    return 0
}

function implementPkg {
    mPush $FAKEROOT/$SDN
    log "{GEN,IMP}|INFO|Setting file in system" t
    processCmd "tar cf - . | (cd / ; tar xvf - )"
    [ $? -gt 0 ] && log "GEN|ERROR|Error during implementation" t && return 1
    sed -e 's/total [0-9]*//' < <(ls -lAR) > /var/log/pkm/implementationLogs/$SDN.log
    [ $? -gt 0 ] && log "GEN|ERROR|Error creating implementation log" t && return 1
    log "Done implementation." t
    mPop
    return 0
}

function cleanup {
    log "GEN|INFO|Cleaning up source file" t
    mPush $SD
    processCmd "rm -fr $SDN"
    [ $? -gt 0 ] && return 1
    mPop
    processCmd "rm -fr $FAKEROOT/$SDN"
    [ $? -gt 0 ] && return 1
    return 0
}

function setCmdFileList {
    log "GEN|INFO|Setting up command files list." t
    if [[ "$SDN" = "" ]]; then
        log "{GEN,ERR}|ERROR|sdn is not set." t
        return 1
    fi
    if [ "$SDNCONF" == "" ]; then
        log "{GEN,ERR}|ERROR|sdnConf not set." t
        return 1
    fi

    DEPCHECKCMDFILE=$SDNCONF/depcheck
    PRECONFIGCMDFILE=$SDNCONF/preconfig
    CONFIGCMDFILE=$SDNCONF/config
    COMPILECMDFILE=$SDNCONF/compile
    CHECKCMDFILE=$SDNCONF/check
    PREINSTALLCMDFILE=$SDNCONF/preinstall
    INSTALLCMDFILE=$SDNCONF/install
    PREIMPLEMENTCMDFILE=$SDNCONF/preimplement
    POSTIMPLEMENTCMDFILE=$SDNCONF/postimplement
    CMDFILELIST=(
        $DEPCHECKCMDFILE
        $PRECONFIGCMDFILE
        $CONFIGCMDFILE
        $COMPILECMDFILE
        $CHECKCMDFILE
        $PREINSTALLCMDFILE
        $INSTALLCMDFILE
        $PREIMPLEMENTCMDFILE
        $POSTIMPLEMENTCMDFILE
    )
    return 0
}

function listTask {
    i=0
    while [[ $i < ${#AUTOINSTALLCMDLIST[@]} ]]; do
        echo -n "${AUTOINSTALLCMDLIST[$i]}, "
        ((i++))
    done
    echo ""
}

function mPush {
    [ ! $1 ] && return 1
    pushd $1 >/dev/null 2>/dev/null
    [ $? -gt 0 ] && quitPkm 1 "Error pushing $1 onto stack." || return 0
}

function mPop {
    popd >/dev/null 2>/dev/null
    [ $? -gt 0 ] && quitPkm 1 "Error poping directory of the stack" || return 0
}

function requestHostBackup {
    log "GEN|INFO|Requesting backup from host." t
    declare backupName
    ## $LFS/var/run from the host will not be the same as within chroot environment
    ## That is why I use /var/log
    declare backupPath="/var/log/pkm/backup"
    [ $1 ] && backupName="LFS_$1" || backupName="LFS"
    echo $backupName > $backupPath
    log "GEN|INFO|Request backupname: $backupName." t
    log "GEN|INFO|Waiting for backup to complete." t
    while true; do
        echo -n '.'
        ls $backupPath > /dev/null 2> /dev/null
        [ $? -gt 0 ] && break;
        sleep 3s
    done
    echo ""
    return 0
}

function evalPrompt {
    case $1 in
        unpack)
            unpack
            ;;
        depcheck)
            log "GEN|INFO|Running dependency check scripts" t
            sourceScript "${DEPCHECKCMDFILE}"
            ;;
        preconfig)
            if [ $HASBUILDDIR -lt 1 ]; then
                mPush $SD/$SDN
            else
                mPush $BUILDDIR
            fi
            sourceScript "${PRECONFIGCMDFILE}"
            log "GEN|INFO|Running pre-config scripts" t
            mPop
            ;;
        config)
            log "GEN|INFO|Running config scripts ${CONFIGCMDFILE}" t
            mPush $BUILDDIR
            sourceScript "${CONFIGCMDFILE}"
            mPop
            ;;
        compile)
            log "GEN|INFO|Running compile scripts" t
            mPush $BUILDDIR
            sourceScript "${COMPILECMDFILE}"
            mPop
            ;;
        check)
            log "GEN|INFO|Running check scripts" t
            mPush $BUILDDIR
            sourceScript "${CHECKCMDFILE}"
            mPop
            ;;
        preinstall)
            log "GEN|INFO|Running PreInstall scripts" t
            mPush $BUILDDIR
            sourceScript "${PREINSTALLCMDFILE}"
            mPop
            ;;
        install)
            log "GENINFO|Running install scripts" t
            mPush $BUILDDIR
            sourceScript "${INSTALLCMDFILE}"
            mPop
            ;;
        preimplement)
            log "GEN|INFO|Running preImplement scripts" t
            mPush $BUILDDIR
            sourceScript "${PREIMPLEMENTCMDFILE}"
            mPop
            ;;
        implement)
            if [[ $BYPASSIMPLEMENT < 1 ]]; then
                log "{GEN,PKG}|WARNING|bypassImplement flag is set, unable to proceed with implement request." t
                return 1
            fi
            log "GEN|INFO|Running implement procedure." t
            implementPkg
            ;;
        postimplement)
            log "GEN|INFO|Running PostImplement scripts" t
            mPush $BUILDDIR
            sourceScript "${POSTIMPLEMENTCMDFILE}"
            mPop
            ;;
        autoinstall)
            autoInstall
            ;;
        cleanup)
            cleanup
            ;;
        loadpkg)
            loadPkg
            ;;
        unloadpkg)
            unloadPkg
            ;;
        backup)
            requestHostBackup $2
            ;;
        installpkm)
            installPkm
            ;;
        dumpenv)
            dumpEnv
            ;;
        listtask)
            listTask
            ;;
        debug)
            if [[ "$2" = "" ]]; then
                return
            fi
            DEBUG=$2
            ;;
        reload)
            readConfig
            ;;
        quit)
            quitPkm $2
            ;;
        *)
            log "GEN|INFO|Unknown command: $1" t
            ;;
    esac

}

function prompt {
    while [[ $CURSTATE == [0] ]]; do
        promptUser "Input."
        read -e command
        evalPrompt $command
    done
}

function quitPkm {
    ## First log exit message if present
    if [ -n "$2" ]; then
        log "GEN|WARNING|Exist Message received: $2"
    fi
    declare ret=0 ## Default exit value
    if [ $1 ]; then ret=$1; fi ## Override exit value

    [ $? -gt 0 ] && echo "ERROR with unMountLfs, CHECK YOUR SYSTEM." && ret=1

    log "GEN|INFO|Closing logs." t
    [ ${GENLOGFD} ] && exec {GENLOGFD}>&-
    [ ${PKGLOGFD} ] && exec {PKGLOGFD}>&-
    [ ${ERRLOGFD} ] && exec {ERRLOGFD}>&-

    unset GENLOGFILE PKGLOGFILE ERRLOGFILE
    unset GENLOGFD PKGLOGFD ERRLOGFD

    if [ -f /var/run/pkm/pkm.lock ]; then
        log "GEN|INFO|Removing pkm lock." t
        rm /var/run/pkm/pkm.lock
        [ $? -gt 0 ] && echo "Error removing lock."
    fi
    if [[ ! "$2" = "" ]]; then
        echo "Quitting message: $2."
    fi
    tput sgr0
    exit $ret
}

function installPkm {
    pkmPath_=/opt/Pkm
    if [ ! -d $pkmPath_ ]; then
        processCmd " install -vdm 0755 $pkmPath_"
        [ $? -gt 0 ] && log "GEN|ERROR|Error install $pkmPath_" t && return 1

    fi
    log "GEN|INFO|Removing old pkm." t
    processCmd "rm -vfr $pkmPath_/*"
    mPush $pkmPath_
    log "GEN|INFO|Downloading Pkm." t
    processCmd " wget https://github.com/ericsimard52/lfs_pkm/archive/master.zip"
    [ $? -gt 0 ] && log "GEN|ERROR|Error downloading pkm from https://github.com/ericsimard52/lfs_pkm/archive/master.zip" t && mPop &&return 1

    log "GEN|INFO|Installing Pkm" t
    processCmd " unzip -o master.zip"
    [ $? -gt 0 ] && log "GEN|ERROR|Error during unzip master.zip" t && mPop && return 1
    processCmd " mv lfs_pkm-master Pkm"
    [ $? -gt 0 ] && log "GEN|ERROR|Error during move" t && mPop && return 1
    processCmd " chown -cR root:root Pkm"
    [ $? -gt 0 ] && log "GEN|ERROR|Error during chown" t && mPop && return 1
    processCmd " rm -v master.zip"
    [ $? -gt 0 ] && log "GEN|ERROR|Error rm master.zip" t && mPop && return 1
    processCmd " cp -vfr $pkmPath_/Pkm/FAKEROOT/* /"
    [ $? -gt 0 ] && log "GEN|ERROR|Error copying pkm in system files." t && mPop && return 1
    mPop
}

singleton ## Ensure only one instance runs.

log "NULL|INFO|Starting PKM" t
readConfig
log "NULL|INFO|Configuration loaded." t
log "NULL|INFO|Starting log managers" t
startLog
prompt
