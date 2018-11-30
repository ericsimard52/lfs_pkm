#!/bin/bash

declare configFile="/root/LFS_Pkm/FAKEROOT/etc/pkm/pkm.conf"
declare devBase="/home/tech/Git/lfs_pkm/FAKEROOT"
declare sd td sdn sdnConf ext hasBuildDir buildDir confBase bypassImplement wgetUrl FAKEROOT
declare unpackCmd
declare MAKEFLAGS
declare DBG_LVL=0 #Change to 1 to turn debug on.
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
        log "NULL|INFO|Creating $genLogFile"
        > $genLogFile
        sudo chmod 666 -v $genLogFile
    fi
    if [ ! -f $pkgLogFile ]; then
        log "NULL|INFO|Creating $pkgLogFile"
        > $pkgLogFile
        sudo chmod 666 -v $pkgLogFile
    fi
    if [ ! -f $impLogFile ]; then
        log "NULL|INFO|Creating $impLogFile"
        > $impLogFile
        sudo chmod 666 -v $impLogFile
    fi
    if [ ! -f $errLogFile ]; then
        log "NULL|INFO|Creating $errLogFile"
        > $errLogFile
        sudo chmod 666 -v $errLogFile
    fi
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
    sudo install -vdm755 /usr/{bin,share/pkm}
    sudo install -g pkm -o pkm -vdm775 /var/{log/pkm,run/pkm,cache/pkm}
    sudo install -vdm755 /etc/pkm
    sudo install -o pkm -g pkm -v -m 664 $FbaseDir/etc/pkm/pkm.conf /etc/pkm/pkm.conf
    sudo install -vm755 $FbaseDir/usr/bin/pkm.sh /usr/bin/pkm.sh
    log "GEN|INFO|Files are installed, changing some dev variable to production." t
    sudo sed -i 's/\/root\/LFS_Pkm\/FAKEROOT\/etc\/pkm\/pkm.conf/\/etc\/pkm\/pkm.conf/g' /usr/bin/pkm.sh
    sudo sed -i 's/\/root\/LFS_Pkm\/FAKEROOT//g' /etc/pkm/pkm.conf

    log "NULL|INFO|Don't forget to add your normal user account to the pkm group."

}

###
# Dump environment variable
###
function dumpEnv {
    echo "GEN:INFO:Environment Var:
buildTmpMode: $buildTmpMode
sd: $sd
tf: $tf
sdnConf: $sdnConf
ext: $ext
hasBuildDir: $hasBuildDir
MAKEFLAGS: $MAKEFLAGS
buildDir: $buildDir
LFS: $LFS
configFile: $configFile
confBase: $confBase
genLog: $genLogFile
genLogFD: $genLogFD
pkgLog: $pkgLogFile
pkgLogFD: $pkgLogFD
impLog: $impLogFile
impLogFD: $impLogFD
errLog: $errLogFile
errLogFD: $errLogFD
"

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
        echo $line
        IFS=':' read -ra PARAM <<< "$line"
        case "${PARAM[0]}" in
            sd) sd=${PARAM[1]};;
            confBase) confBase=${PARAM[1]};;
            MAKEFLAGS) MAKEFLAGS=${PARAM[1]};;
            FAKEROOT) FAKEROOT=${PARAM[1]};;
            bypassImplement) bypassImplement=${PARAM[1]};;
            genLog) genLogFile=${PARAM[1]};;
            pkgLog) pkgLogFile=${PARAM[1]};;
            errLog) errLogFile=${PARAM[1]};;
            impLog) impLogFile=${PARAM[1]};;
            \#|\#\#|\#\#\#) log "NULL|INFO|COMMENT";;
            *) log "NULL|WARNING|Unknown config param" t;;
        esac
        unset IFS
    done < $configFile
    export MAKEFLAGS
    log "NULL|INFO|Done reading log file." t
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
# Params "PIPE:{INFO,WARNING,ERROR,FATAL}:MESSAGE" PRINTtoSTDOUT
# When PIPE is set, the parameters sent through the pipe depends on the pipe.
# When no PIPE is set, it will set to /dev/null
# genLogPipe will receive :STARTLOG: to begin a log session
#   Log format: LEVEL:MSG.
# pkgLogPipe; This log contains all building logs from a given package.
#   Start session :STARTLOG:PACKAGE
#   Log format: LEVEL:MSG
#   End session: :ENDLOG:PACKAGE
# impLogPipe;
#   Start session:  :STARTLOG:PACKAGE
#   Log format: :ACTION:TYPE:FILE
#   End session: :ENDLOG:PACKAGE
# errLogPipe;
#   Start session :STARTLOG:
#   Log format: :LEVEL:MESSAGE
#   End session: :ENDLOG:
###
function log {
    declare LEVEL COLOR MSG M
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

    MSG=$COLOR$LEVEL" - "$sdn":"$M$MSGEND ## Full message string

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
            echo $M >&${FDs[$i]}
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
        echo $M >&${FDs[$i]}
        ((i++))
    done
    unset IFS FDs LEVEL COLOR MSG M MSGEND i
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
        log "ERR|ERROR|Configuration not found for $pkg"
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
    readConfig
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

    eval $unpackCmd
    if [ $hasBuildDir == 0 ]; then
        log "PKG|INFO|Creating build directory" true
        mkdir -v $sd/$sdn/build
    fi

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
        log "{GEN,ERR}|FATAL|pushd to $FAKEROOT/$sdn failed." true
        exit 1
    fi

    log "{GEN,IMP}|INFO|Setting file in system" true
    sudo su -c "tar cvf - . | (cd / ; tar vxf - ) | tee >> /var/cache/pkm/$sdn"
    popd > /dev/null 2>&1
}

###
# Cleanup after package source and fakeroot directories
###
function cleanup {
    log "GEN|INFO|Cleaning up source file" true
    pushd $sd > /dev/null
    if [[ $? > 0 ]]; then
        log "{GEN,ERR}|FATAL|pushd to $sd failed." true
        exit 1
    fi

    sudo rm -fr $sdn
    popd > /dev/null 2>&1

    promptUser "Remove Fakeroot Files? Y/n"
    read x
    case $x in
        [nN])
            log "GEN|INFO|Leaving fakeroot in place." true
            ;;
        [yY]|*)
            log "GEN|INFO|Removing fakeroot." true
            sudo rm -fr $FAKEROOT/$sdn
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
        return
    fi
    if [ "$sdnConf" == "" ]; then
        log "{GEN,ERR}|ERROR|sdnConf not set." true
        return
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
}

###
# Preparation of a new package
###
function prepPkg {
    unloadPkg
    promptUser "Package name?"
    read -e pkg

    # If we can't file the package (source tar), we do a search for the term provided by the user.
    if [ ! -f $sd/$pkg ]; then
        log "GEN|INFO|Package not found in $sd, searching for variants." true

        declare -a foundFiles
        for file in `find $sd -maxdepth 1 -type f -iname "$pkg*"`; do
            promptUser "FoundFiles: $file\n Use it? Y/n"
            read u
            case $u in
                [nN])
                    continue
                    ;;
                [yY]|*)
                    log "GEN|INFO|Using: $file" true
                    pkg=$(basename $file)
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
            return
        fi

    fi
    tf=$pkg
    sdn="${tf%.tar.*}" # Get the filename
    promptUser "sdn: $sdn, is that correct? Y/n"
    read us
    case $us in
        [nN])
            promptUser "Enter correct sdn."
            read sdn
            ;;
        [yY]|*)
            log "NULL|INFO|Thank you." t
            ;;
    esac
    sdnConf="$confBase/$sdn"
    setCmdFileList

    if [ -d $sdnConf ]; then
        log "GEN|WARNING|Config Directory exists. Previous configuration file will be left intact." true
    else
        md="sudo mkdir -vp $sdnConf/"
        log "GEN|INFO|Creating package configuration directory: $md" true
        eval $md
        if [[ $? > 0 ]]; then
            evalError $cmd
            return
        fi
        log "PKG|INFO|$sdnConf created" true
    fi
    echo -n "Does the package requires a build directory? y/N "
    read d
    case $d in
        [yY])
            log "PKG|INFO|Adjusting script config for build directory" true
            buildDir="$sd/$sdn/build"
            hasBuildDir=0
            ;;
        *)
            buildDir="$sd/$sdn"
            hasBuildDir=1
            ;;
    esac

    log "PKG|INFO|Creating general config file with default values." true
    tconf="tf:$tf\nsdn:$sdn\nhasBuildDir:$hasBuildDir\nbypassImplement:1\ntasks:unpack,implement,cleanup\nwgetUrl:"
    genConfigFile="$sdnConf/$sdn.conf"
    sudo touch $genConfigFile
    sudo chmod 666 $genConfigFile
    sudo echo -e $tconf > "${genConfigFile}"

    cmdArrLen=${#cmdFileList[@]}
    log "PKG|INFO|Installing configuration files." true
    t=0
    while [ $t -lt $cmdArrLen ]; do
        fn=${cmdFileList[$t]}
        if [ -f $fn ]; then
            log "PKG|WARNING|Old config file present." true
        else
            log "PKG|INFO|Creating $fn"
            tc="sudo touch $fn && sudo chmod 755 $fn"
            eval $tc
        fi
        ((t++))
    done

    log "PKG|INFO|Configuration created." true

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
            pushd $buildDir
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
        dumpenv)
            dumpEnv
            ;;
        switchmode)
            switchMode
            ;;
        reload)
            readConfig
            ;;
        quit)
            log "GEN|INFO|Quitting"
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
log "NULL|INFO|Testing pkm installation." t

prompt
