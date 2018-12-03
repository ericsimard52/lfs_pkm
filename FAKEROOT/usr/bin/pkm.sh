#!/bin/bash

declare configFile="/root/LFS_Pkm/FAKEROOT/etc/pkm/pkm.conf"
declare devBase="/home/tech/Git/lfs_pkm/FAKEROOT"
declare sd td sdn sdnConf pkg ext hasBuildDir buildDir confBase bypassImplement wgetUrl FAKEROOT
declare unpackCmd
declare MAKEFLAGS
declare DEBUG=0 # 0=OFF, 1= ON, but not to stdout, send all debug to log file. 2= send to stdout and logfile
declare genLogFile pkgLogFile impLogFile errLogFile
declare genLogFD pkgLogFD impLogFD errLogFD #File descriptor input only
declare isImplemented=1 # This changes to 0 when implementation is done.
declare CURSTATE=0 # Set to 1 to exit program succesfully


# Config files
declare genConfigFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile
declare preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile
declare -a cmdFileList
declare -a autoInstallCmdList
function singleton {
    if [ ! -d /var/run/pkm ]; then
        log "NULL|FATAL|Directory /var/run/pkm does not exists. Do you need to run installPkm?" t
        return
    fi
    if [ -f /var/run/pkm/pkm.lock ]; then
        log "NULL|FATAL|Pkm is already running or has not quit properly, in that case, remove /var/run/pkm/pkm.lock" t
        return
    fi
    touch /var/run/pkm/pkm.lock
}

function importLfsScriptedImplementLogs {
    pushd /var/log/pkm
    for file in `find . -name *implement*`; do
        cp -v $file /var/cache/pkm/
    done
    popd
}

function startLog {
    if [ ! -f $genLogFile ]; then
        log "NULL|INFO|Creating $genLogFile" t
        > $genLogFile
        chmod 666 -v $genLogFile
    fi
    if [ ! -f $pkgLogFile ]; then
        log "NULL|INFO|Creating $pkgLogFile" t
        > $pkgLogFile
        chmod 666 -v $pkgLogFile
    fi
    if [ ! -f $impLogFile ]; then
        log "NULL|INFO|Creating $impLogFile" t
        > $impLogFile
        chmod 666 -v $impLogFile
    fi
    if [ ! -f $errLogFile ]; then
        log "NULL|INFO|Creating $errLogFile" t
        > $errLogFile
        chmod 666 -v $errLogFile
    fi
    log "NULL|INFO|Creating file descriptor for logs" t t
    exec {genLogFD}>$genLogFile
    exec {pkgLogFD}>$pkgLogFile
    exec {impLogFD}>$impLogFile
    exec {errLogFD}>$errLogFile
}

function installManager {
    userId=`id -u`
    if [[ $userId -gt 0 ]]; then
        log "NULL|INFO|Run install manager as root." t
        exit 1
    fi

    FbaseDir=$devBase
    log "NULL|INFO|Check if user and group pkm exists" t
    ucount=`</etc/passwd grep pkm | wc -l`
    if [[ $ucount < 1 ]]; then
        log "NULL|INFO|Creating user pkm" t
        useradd -c "PKM User" -s /bin/false -M -r -U pkm
    fi
    gcount=`</etc/group grep pkm | wc -l`
    if [[ $gcount < 1 ]]; then # No pkm group, the user creation should have created it, but lets do it.
        log "NULL|INFO|Creating pkm group" t
        groupadd -r pkm
    fi

    log "GEN|INFO|Installing pkm." t
    install -g pkm -o pkm -vdm755 /usr/{bin,share/pkm}
    install -g pkm -o pkm -vdm775 /var/{log/pkm,run/pkm,cache/pkm}
    install -g pkm -o pkm -vdm775 /etc/pkm/templates
    install -g pkm -o pkm $FbaseDir/etc/pkm/templates/* /etc/pkm/templates
    if [ ! -f /etc/pkm/pkm.conf ]; then
        install -o pkm -g pkm -v -m 664 $FbaseDir/etc/pkm/pkm.conf /etc/pkm/pkm.conf
    fi
    install -vm755 $FbaseDir/usr/bin/pkm.sh /usr/bin/pkm.sh
    log "GEN|INFO|Files are installed, changing some dev variable to production." t
    sed -i 's/\/root\/LFS_Pkm\/FAKEROOT\/etc\/pkm\/pkm.conf/\/etc\/pkm\/pkm.conf/g' /usr/bin/pkm.sh
    sed -i 's/\/root\/LFS_Pkm\/FAKEROOT//g' /etc/pkm/pkm.conf

    log "NULL|INFO|Don't forget to add your normal user account to the pkm group."
}

###
# Dump environment variable
###
function dumpEnv {
    printf "\e[1mEnvironment Var:\e[0m
\e[34mDEBUG: \e[32m$DEBUG
\e[34msd: \e[32m$sd
\e[34mtf: \e[32m$tf
\e[34msdnConf: \e[32m$sdnConf
\e[34mext: \e[32m$ext
\e[34mhasBuildDir: \e[32m$hasBuildDir
\e[34mMAKEFLAGS: \e[32m$MAKEFLAGS
\e[34mbuildDir: \e[32m$buildDir
\e[34mLFS: \e[32m$LFS
\e[34mconfigFile: \e[32m$configFile
\e[34mconfBase: \e[32m$confBase
\e[34mgenLog: \e[32m$genLogFile
\e[34mgenLogFD: \e[32m$genLogFD
\e[34mpkgLog: \e[32m$pkgLogFile
\e[34mpkgLogFD: \e[32m$pkgLogFD
\e[34mimpLog: \e[32m$impLogFile
\e[34mimpLogFD: \e[32m$impLogFD
\e[34merrLog: \e[32m$errLogFile
\e[34merrLogFD: \e[32m$errLogFD\e[0m\n"
}

###
# Read config file stored in $configFile
###
function readConfig {
    log "NULL|INFO|Reading configuration file." t
    if [ ! -f $configFile ]; then
        log "NULL|ERROR|Configuration file: /etc/pkm/pkm.conf is missing. Do you need to run installManager?" t
        return 1
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
                sd=${PARAM[1]}
                log "NULL|INFO|Set param sd:$sd" t t
                ;;
            confBase)
                confBase=${PARAM[1]}
                log "NULL|INFO|Set param confBase:$confBase" t t
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
                bypassImplement=${PARAM[1]}
                log "NULL|INFO|Set param bypassImplement:$bypassImplement" t t
                ;;
            genLog)
                genLogFile=${PARAM[1]}
                log "NULL|INFO|Set param genLogFile:$genLogFile" t t
                ;;
            pkgLog)
                pkgLogFile=${PARAM[1]}
                log "NULL|INFO|Set param pkgLogFile:$pkgLogFile" t t
                ;;
            errLog)
                errLogFile=${PARAM[1]}
                log "NULL|INFO|Set param errLogFile:$errLogFile" t t
                ;;
            impLog)
                impLogFile=${PARAM[1]}
                log "NULL|INFO|Set param impLogFile:$impLogFile" t t
                ;;
            "#") continue;;
            *) continue;;
        esac
        unset IFS
    done < $configFile
    export MAKEFLAGS
    log "NULL|INFO|Done reading config file." t
}

function processCmd {
    local cmd
    if [[ $DEBUG = 0 ]]; then
        cmd="$1 2>&1 >/dev/null"
    elif [[ $DEBUG = 1 ]]; then
        cmd="$1 2>&${errLogFD} >&${pkgLogFD}"
    else
        cmd="$1 > >(tee >(cat - >&${pkgLogFD})) 2> >(tee >(cat - >&${errLogFD}) >&2)"

    fi
    log "GEN|INFO|Processing command: $cmd" t
    eval $cmd
    log "GEN|INFO|Done processing." t t
    return $?
}
function fetchPkg {
    while read -r line; do
        echo $line
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
        esac
        unset IFS
    done < $configFile

    if [[ "$wgetUrl" = "" ]]; then
        log "{GEN,ERR}|ERROR|No url provided. Adjust config file." t
        return
    fi
    wget $wgetUrl $sd/
}

###
# Params "FDs|LEVEL|MESSAGE" PRINTtoSTDOUT DEBUGONLY
# FDs define 1 or more file descriptor to send the message to. Possible option: GEN,PKG,IMP,ERR
#
# GEN for general log, this log is active when debug is off. Contains general message about progress and results
# PKG Used to log details when debug is on. contains logs from fetching packages  up to installation.
# IMP Used when debug is on to store details about the implementation process from preimplement to postimplement
#     This does not store the information about where files are installed. Those are separate and always active.
# ERR Used when debug is on to store details about the error
# NOTE: More the 1 FD per call can be provided: log "{GEN,ERR}|...."
# PRINTtoSTDOUT when set, also print the message to stdout
#
# DEBUGONLY When set instruct to process log only when debug is on.
###
function log {
    if [ $3 ] && [ $DEBUG = 0 ]; then
        return
    fi
    declare LEVEL COLOR MSG M CALLER
    declare -a FDs # Array of file descriptor where messages needs to be redirected to.
    MSGEND="\e[0m" ## Clear all formatting
    IFS='|' read -ra PARTS <<< $1
    case "${PARTS[0]}" in
        \{*)
            IFS=',' read -ra DEST <<< ${PARTS[0]}
            i=0
            while [[ $i < ${#DEST[@]} ]]; do
                t="${DEST[$i]}"
                t="${t/\}}"
                t="${t/\{}"
                case "$t" in
                    GEN) FDs+=($genLogFD);;
                    PKG) FDs+=($pkgLogFD);;
                    IMP) FDs+=($impLogFD);;
                    ERR) FDs+=($errLogFD);;
                esac
                ((i++))
            done
            IFS='|'
            ;;
        GEN) FDs+=($genLogFD);;
        PKG) FDs+=($pkgLogFD);;
        IMP) FDs+=($impLogFD);;
        ERR) FDs+=($errLogFD);;
        NULL|*) FDs+=();;
    esac

    ### Set color formatting
    case "${PARTS[1]}" in
        INFO)
            LEVEL=INFO
            COLOR="\e[34m"
            ;;
        WARNING)
            LEVEL=WARNING
            COLOR="\e[33m"
            ;;
        ERROR)
            LEVEL=ERROR
            COLOR="\e[91m"
            ;;
        FATAL)
            LEVEL=FATAL
            COLOR="\e[91m"
            ;;
    esac

    ### Append message provided by caller
    M="${PARTS[2]}"
    if [[ "$M" = "" ]]; then
        log "NULL|ERROR|Empty log message?!?!" t
    fi

    if [ $sdn ]; then
        caller="\e[32m"$pkg"\e[0m "
        callerLog=$pkg
    else
        callerLog="NONE"
        caller="\e[32mNONE\e[0m "
    fi
    MSG=$COLOR$LEVEL" - "$caller":"$COLOR$M$MSGEND ## Full message string
    LOGMSG=$LEVEL" - "$callerLog":"$M
    if [[ $DEBUG > 0 ]] && [ $3 ]; then
        MSG="\e[33mDEBUG\e[0m - "$MSG
    fi

    ### If $2 is set we also print to stdout.
    if [[ $2 ]]; then
        if [[ ! $FDs ]]; then
            echo -e "NO_DESTINATION -- "$MSG
            return
        fi
        i=0
        displayOnce=0
        while [[ $i < ${#FDs[@]} ]]; do
            if [[ $displayOnce = 0 ]]; then
                echo -e "${FDs[$i]} -- "$MSG
                displayOnce=1 ## Prevents repeat message to stdout when multiple destination are provided.
            fi
            echo $LOGMSG >&${FDs[$i]}
            ((i++))
        done
        unset IFS FDs LEVEL COLOR MSG M MSGEND i
        return
    fi

    ### $2 not set, we do not print to stdout
    if [[ ! $FDs ]]; then
        echo -e "NO_DESTINATION -- "$MSG
    fi
    i=0
    while [[ $i < ${#FDs[@]} ]]; do
        echo -e "${FDs[$i]} -- "$MSG
        echo $LOGMSG >&${FDs[$i]}
        ((i++))
    done
    unset IFS FDs LEVEL COLOR MSG M MSGEND i CALLER
}

###
# Enumerate through commans stores in commands array
# all does not work as intended
###
function listCommands {
    declare cmd
    COLOR="\e[32]"
    promptUser "Which command?"
    read x
    case $x in
        preconfig | all)
            c="cat $preConfigCmdFile"
            eval $c | tee -a 2>> $ld/${lf[0]}
            ;;
        config | all)
            i=0
            ;;
        compile | all)
            i=0
            ;;
        check | all)
            i=0
            ;;
        preInstall | all)
            i=0
            ;;
        install | all)
            i=0
            ;;
        preImplement | all)
            i=0
            ;;
        postImplement | all)
            i=0
            ;;

    esac


}

###
# Provide this command with a string parameter representing the prompt to the user.
# This function is here to ensure standard user prompt throught the application
###
function promptUser {
    COLOR="\e[37m"
    echo -en $COLOR$1" : \e[0m"
}

function checkInstalled {
    command -v $1 > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,PKG,ERR}|ERROR|$1 is not installed but is required by $pkg" t
        return 1
    fi
    return 0
}

function checkVersion {
    reqCmd=$1
    reqVer=$2
    cmdVersion=`$1 --version |head -n1 | egrep -o "([0-9]{1,}\.)+[0-9]{1,}"`
    vercomp $cmdVersion $reqVer
    return $?
}

function vercomp {
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i installedVer=($1) neededVer=($2)
    for ((i=${#installedVer[@]}; i<${#neededVer[@]}; i++));do
        installedVer[i]=0
    done
    for ((i=0; i<${#installedVer[@]}; i++)); do
        if [[ -z ${neededVer[i]} ]]; then
            neededVer[i]=0
        fi
        if ((${installedVer[i]} > ${neededVer[i]})); then
            return 0
        fi
        if ((${installedVer[i]} < ${neededVer[i]})); then
            return 1
        fi
    done
    log "{GEN,ERR}|FATAL|Should not reach this point in vercomp. Unable to ensure proper version is installed." t
    return 0
}


function loadPkg {
    if [[ ! "$pkg" == "" ]]; then
        log "GEN|INFO|Unloading previous package from memory." true
        unloadPkg
    fi
    promptUser "Which package?"
    read pkg
    if [[ "$pkg" == "" ]]; then
        log "ERR|INFO|Empty package provided..."
        return
    fi
    if [ ! -d $confBase/$pkg ]; then
        declare -a foundFiles
        for file in `find $confBase -maxdepth 1 -type d -iname "$pkg*"`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "GEN|INFO|Using: $file" true
                    pkg=$(basename $file)
                    if [ ! -d $confBase/$pkg ]; then
                        log "ERR|FATAL|Could not find $pkg after finding it????" true
                        return
                    fi
                    break
                    ;;
            esac
        done
        if [ ! -d $confBase/$pkg ]; then
            log "ERR|FATAL|No package found for $pkg." true
            return
        fi
    fi
    sdnConf=$confBase/$pkg
    genConfigFile="$sdnConf/$pkg.conf"
    if [ ! -f $genConfigFile ]; then
        log "ERR|ERROR|Package general config file missing" t
        return
    fi

    log "GEN|INFO|Reading config file into variables" t
    while read -r line; do
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            tf) tf=${PARAM[1]};;
            sdn) sdn=${PARAM[1]};;
            sd) sd=${PARAM[1]};;
            hasBuildDir) hasBuildDir=${PARAM[1]};;
            bypassImplement) bypassImplement=${PARAM[1]};;
            wgetUrl) wgetUrl=${PARAM[1]};;
            tasks)
                IFS=',' read -ra TASK <<< "${PARAM[1]}"
                x=0
                while [[ $x < ${#TASK[@]} ]]; do
                    autoInstallCmdList+=(${TASK[$x]})
                    ((x++))
                done
                IFS=':'
                ;;
            DEBUG) DEBUG=${PARAM[1]};;
            *) log "{GEN,ERR}|ERROR|Unknow params: ${PARAMS[1]}" t;;
        esac
        unset IFS
    done < $genConfigFile


    log "GEN|INFO|Check if source package exists" t
    # Check if source package exists
    if [ ! -f $sd/$tf ]; then
        log "{GEN,ERR}|ERROR|Package $tf not found in source $sd" t
        return
    fi

    ext="${tf##*.}"
    sdnConf="$confBase/$sdn"
    setCmdFileList
    if [ $hasBuildDir -lt 1 ]; then
        buildDir=$sd/$sdn/build
        log "GEN|INFO|Checking if build dir: $buildDir exists." t t
        if [ ! -d "$builDir" ]; then
            log "GEN|WARNING|Build directory flag set, but dir does not exist, creating..." t t
            install -vdm755 $buildDir
        fi
    else
        buildDir=$sd/$sdn
    fi

    ### Not needed with the new pipe logs.
    #    logDir="/var/log/pkm/$sdn"
    #    log "GEN|INFO|Checking log directorie: $ld" t
    #    if [ ! -d "$logDir" ]; then
    #        log "{GEN,ERR}|WARNING|Package log directory not found, creating." true
    #        mkdir $logDir
    #    fi

    # Adjusting the unpack commands
    log "GEN|INFO|Adjusting unpack command." true
    if [[ "$ext" == "xz" ]]; then
        unpackCmd="tar xvf $tf"
    elif [[ "$ext" == "gz" ]]; then
        unpackCmd="tar xvfz $tf"
    elif [[ "$ext" == "gzip" ]]; then
        unpackCmd="tar xvfz $tf"
    elif [[ "$ext" == "bz2" ]]; then
        unpackCmd="tar xvfj $tf"
    elif [[ "$ext" == "tgz" ]]; then
        unpackCmd="tar xvfz $tf"
    else
        log "ERR|FATAL|Unknown package unpack method." true
        return
    fi
}

###
# Unload package from memory, reset environment variable to their default and call readConfig to reload configuration.
###
function unloadPkg {
    unset -v pkg sdnConf tf sdn hasBuildDir buildDir ld ext unpackCmd banner genConfigFile preconfigCmdFile configCmdFile compileCmdFile checkCmdFile preInstallCmdFile installCmdFile preImplementCmdFile postImplementCmdFile cmdFileList preconfigCmd configCmd compileCmd checkCmd preInstallCmd installCmd preImplementCmd postImplementCmd autoInstallCmdList
    isImplemented=1
}

###
# Call to unpack source code.
# The unpackCmd is set when loadPkg is called.
###
function unpack {
    log "{GEN,PKG}|INFO|Unpacking source code $tf" true

    if [ ! -f $sd/$tf ]; then
        log "{GEN,PKG,ERR}|FATAL|$tf not found." true
        return 1
    fi

    log "PKG|INFO|Running Cmd: $unpackCmd" true
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,PKG,ERR}|FATAL|pushd to $sd failed." true
        return 2
    fi
    processCmd "${unpackCmd}"
    if [ $hasBuildDir == 0 ]; then
        log "PKG|INFO|Creating build directory" true
        processCmd "install -opkm -gpkm -vdm755 $sd/$sdn/build"
    fi

    log "{GEN,PKG}|INFO|Done." t
    popd > /dev/null 2>&1
}

###
# Auto install takes its task list from the package config file.
# This function will simply display the list of task and request confirmation from the user.
###
function autoInstall {
    log "GEN|INFO|AutoInstall: Will be running the following tasks:"
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo "${autoInstallCmdList[$i]}"
        ((i++))
    done
    promptUser "Do you want to start now?"
    read y
    case $y in
        [nN])
            return
            ;;
        [yY]|*)
            runAutoInstall
            ;;
    esac
}

###
# Run the autoinstall
###
function runAutoInstall {
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        f=${autoInstallCmdList[$i]}
        fbase=$(basename $f)
        echo "$fbase"
        if [ "$fbase" = "postImplement" ]; then
            if [[ $bypassImplement > 0 ]]; then
                log "GEN|INFO|Post Implement detected, running Implement first." true
                implementPkg
                isImplemented=0
            else
                log "GEN|INFO|Post Implement detected, and bypass Implement flag is set." true
            fi
        fi
        log "GEN|INFO|Sourcing $f." true
        evalPrompt $fbase
        res=$?
        if [[ $res > 0 ]]; then
            log "{PKG,ERR}|ERROR|Error sourcing $f." true
            return $res
        fi
        if [ "$fbase" = "check" ]; then
            promptUser "Just finished checks, verify it. Do I keep going? Y/n"
            read t
            case $t in
                [Nn])
                    return 1
                    ;;
                [Yy]|*)
                    ((i++))
                    continue
                    ;;
            esac
        fi
        ((i++))
    done

    if [[ $isImplemented > 0 ]]; then
        log "{GEN,PKG}|INFO|Implementing pkg." t
        implementPkg
        isImplemented=0
    fi
    cleanup
    return 0
}

###
# Sourcing our commmands scripts here
###
function sourceScript {
    c=$1
    log "GEN|INFO|Sourcing: $c" true
    source $c
    res=$?
    log "GEN|INFO|Sourced $c returned: $res" true
    return $res
}

###
# Implement package into real root
###
function implementPkg {
    pushd $FAKEROOT/$sdn > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|pushd to $FAKEROOT/$sdn failed." t
        exit 1
    fi

    log "{GEN,IMP}|INFO|Setting file in system" t
    processCmd "sudo su -c \"tar cf - . | (cd / ; tar xvf - )\""
    log "Done implementation." t
    popd > /dev/null 2>&1
}

###
# Cleanup after package source and fakeroot directories
###
function cleanup {
    log "GEN|INFO|Cleaning up source file" t
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|pushd to $sd failed." t
        exit 1
    fi

    rm -fr $sdn
    popd > /dev/null 2>&1

    promptUser "Remove Fakeroot Files? Y/n"
    read x
    case $x in
        [nN])
            log "GEN|INFO|Leaving fakeroot in place." true
            ;;
        [yY]|*)
            log "GEN|INFO|Removing fakeroot." true
            rm -fr $FAKEROOT/$sdn
            log "GEN|INFO|Done." t
            ;;
    esac

}

###
# Populate cmd files variable
###
function setCmdFileList {
    log "GEN|INFO|Setting up command files list." true
    if [ "$sdn" == "" ]; then
        log "{GEN,ERR}|ERROR|sdn is not set." true
        return 1
    fi
    if [ "$sdnConf" == "" ]; then
        log "{GEN,ERR}|ERROR|sdnConf not set." true
        return 1
    fi

    preconfigCmdFile=$sdnConf/preconfig
    configCmdFile=$sdnConf/config
    compileCmdFile=$sdnConf/compile
    checkCmdFile=$sdnConf/check
    preInstallCmdFile=$sdnConf/preinstall
    installCmdFile=$sdnConf/install
    preImplementCmdFile=$sdnConf/preimplement
    postImplementCmdFile=$sdnConf/postimplement
    cmdFileList=(
        $preconfigCmdFile
        $configCmdFile
        $compileCmdFile
        $checkCmdFile
        $preInstallCmdFile
        $installCmdFile
        $preImplementCmdFile
        $postImplementCmdFile
    )
    return 0
}

function downloadPkg {
    declare -a urls
    done=0
    log "GEN|INFO|Downloading packages, enter 1 url per line, finish with empty line." t
    while [ $done -lt 1 ];do
        read u
        if [ "$u" = "" ];then
            done=1
            continue
        fi
        urls+=(${u})
    done
    x=0
    pushd /tmp >/dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|Unable to pushd $sd" t
        return
    fi
    while [ $x -lt ${#urls[@]} ]; do
        wget ${urls[$x]}
        ((x++))
    done
    popd
    unset x urls done
}

function searchPkg {
    # If we can't file the package (source tar), we do a search for the term provided by the user.
    declare -a foundFiles
    for file in `find $sd -maxdepth 1 -type f -iname "$1*"`; do
        promptUser "FoundFiles: $file\n Use it? Y/n"
        read u
        case $u in
            [nN])
                continue
                ;;
            [yY]|*)
                log "GEN|INFO|Using: $file" true
                pkg=$(basename $file)
                log "{GEN,PKG}|INFO|pkg set to $pkg" t t
                if [ ! -f $sd/$pkg ]; then
                    log "{GEN,ERR}|FATAL|Could not find $pkg after finding it????" true
                    return
                fi
                break
                ;;
        esac
    done
    if [ ! -f $sd/$pkg ]; then
        log "GEN|WARNING|No package found for $pkg*." true
        promptUser "Do you want to download? Y/n"
        read u
        case $u in
            [nN])
                pkg="NA"
                return
                ;;
            [yY]|*)
                downloadPkg
                pkg="NA"
                return
                ;;
        esac
    fi
}

function createSkeleton {
    if [ -d $sdnConf ]; then
        log "GEN|WARNING|Config Directory exists. Previous configuration file will be left intact." t
        return
    fi
    install -vdm755 $sdnConf

    echo -n "Does the package requires a build directory? y/N "
    read d
    case $d in
        [yY])
            log "GEN|INFO|Adjusting script config for build directory" t
            buildDir="$sd/$sdn/build"
            hasBuildDir=0
            ;;
        *)
            buildDir="$sd/$sdn"
            hasBuildDir=1
            ;;
    esac

    log "GEN|INFO|Creating general config file with default values." t
    tconf="tf:$tf\nsdn:$sdn\nhasBuildDir:$hasBuildDir\nbypassImplement:1\ntasks:unpack,implement,cleanup"
    genConfigFile="$sdnConf/$sdn.conf"
    touch $genConfigFile
    chmod 666 -v $genConfigFile
    sudo chown -v pkm:pkm $genConfigFile
    echo -e $tconf > "${genConfigFile}"

    cmdArrLen=${#cmdFileList[@]}
    log "GEN|INFO|Installing configuration files." t
    install -g pkm -o pkm -m664 -v $confBase/templates/* $sdnConf/
    log "GEN|INFO|Done." t

}

###
# Preparation of a new package
###
function prepPkg {
    unloadPkg
    promptUser "Package name?"
    read -e inputPkg
    if [ "$inputPkg" = "" ]; then
        log "GEN|INFO|Empty package provided." t
        return
    fi
    searchPkg $inputPkg
    if [ "$pkg" = "NA" ]; then
        return
    fi
    tf=$pkg
    sdn=`tar -tf $sd/$tf |egrep '^[^/]+/?$'`
    sdn="${sdn::-1}"
    log "GEN|INFO|snd set to: $sdn" t t
    sdnConf="$confBase/$sdn"
    log "GEN|INFO|sdnConf set to: $sdnConf" t t
    setCmdFileList
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|ERROR|setCmdFileList returned 1 unable to continue." t t
        return 1
    fi
    createSkeleton
}


###
# List tasks to perform for the current package
###
function listTask {
    i=0
    while [[ $i < ${#autoInstallCmdList[@]} ]]; do
        echo -n "${autoInstallCmdList[$i]}, "
        ((i++))
    done
    echo ""
}

###
# Evaluate user commands from the general prompt.
###
function evalPrompt {
    case $1 in
        listcommands)
            listCommands
            ;;
        fetch)
            fetchPkb
            ;;
        unpack)
            unpack
            ;;
        preconfig)
            if [ $hasBuildDir -lt 1 ]; then
                pushd $sd/$sdn > /dev/null
            else
                pushd $buildDir >/dev/null
            fi
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preconfigCmdFile}"
            log "GEN|INFO|Running pre-config scripts" true
            popd > /dev/null 2>&1
            ;;
        config)
            log "GEN|INFO|Running config scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${configCmdFile}"
            popd > /dev/null 2>&1
            ;;
        compile)
            log "GEN|INFO|Running compile scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                exit 1
            fi
            sourceScript "${compileCmdFile}"
            popd > /dev/null 2>&1
            ;;
        check)
            log "GEN|INFO|Running check scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${checkCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preinstall)
            log "GEN|INFO|Running PreInstall scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preInstallCmdFile}"
            popd > /dev/null 2>&1
            ;;
        install)
            log "GENINFO|Running install scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${installCmdFile}"
            popd > /dev/null 2>&1
            ;;
        preimplement)
            log "GEN|INFO|Running preImplement scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${preImplementCmdFile}"
            popd > /dev/null 2>&1
            ;;
        implement)
            if [[ $bypassImplement < 1 ]]; then
                log "{GEN,ERR}|ERROR|bypassImplement flag is set, unable to proceed with implement request." t
                return 1
            fi
            log "GEN|INFO|Running implement procedure." t
            implementPkg
            ;;
        postimplement)
            log "GEN|INFO|Running PostImplement scripts" true
            pushd $buildDir > /dev/null
            if [[ $? > 0 ]]; then
                log "ERR|FATAL|pushd to $buildDir failed." true
                return 1
            fi
            sourceScript "${postImplementCmdFile}"
            popd > /dev/null 2>&1
            ;;
        autoinstall)
            autoInstall
            ;;
        listtask)
            listTask
            ;;
        cleanup)
            cleanup
            ;;
        preppkg)
            prepPkg
            ;;
        loadpkg)
            loadPkg
            ;;
        unloadpkg)
            unloadPkg
            ;;
        backup)
            requestHostBackup
            ;;
        installpkm)
            installManager
            ;;
        downloadpkg)
            downloadPkg
            ;;
        dumpenv)
            dumpEnv
            ;;
        switchmode)
            switchMode
            ;;
        debug)
            DEBUG=$2
            ;;
        reload)
            readConfig
            ;;
        quit)
            log "GEN|INFO|Quitting"
            exec {genLogFD}>&-
            exec {pkgLogFD}>&-
            exec {impLogFD}>&-
            exec {errLogFD}>&-
            unset genLogFile pkgLogFile impLogFile errLogFile
            unset genLogFD pkgLogFD impLogFD errLogFD

            if [ -f /var/run/pkm/pkm.lock ]; then
                log "GEN|INFO|Removing pkm lock." t
                rm -v /var/run/pkm/pkm.lock
            fi
            CURSTATE=1
            ;;
        ilsil)
            importLfsScriptedImplementLogs
            ;;
        *)
            log "GEN|INFO|Unknown command: $1" t
            ;;
    esac

}

###
# Prompt user for command and send user input to evalPrompt
###
function prompt {
    while [[ $CURSTATE == [0] ]]; do
        promptUser "Input."
        read -e command
        evalPrompt $command
    done
}

## Checking user parameters
for arg in "$@"
do
    case "$arg" in
        --installManager)
            installManager
            exit 0
            ;;
    esac
done


singleton ## Ensure only one instance runs.

log "NULL|INFO|Starting PKM" t
readConfig
log "NULL|INFO|Configuration loaded." t
log "NULL|INFO|Starting log managers" t
startLog
prompt
