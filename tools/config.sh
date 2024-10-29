#!/bin/bash

if [ -z $IDF_PATH ]; then
	export IDF_PATH="$PWD/esp-idf"
fi

if [ -z $IDF_BRANCH ]; then
	IDF_BRANCH="release/v4.4"
fi

if [ -z $AR_PR_TARGET_BRANCH ]; then
	AR_PR_TARGET_BRANCH="release/v2.x"
fi

if [ -z $IDF_TARGET ]; then
	if [ -f sdkconfig ]; then
		IDF_TARGET=`cat sdkconfig | grep CONFIG_IDF_TARGET= | cut -d'"' -f2`
		if [ "$IDF_TARGET" = "" ]; then
			IDF_TARGET="esp32"
		fi
	else
		IDF_TARGET="esp32"
	fi
fi

# DEPENDENCY VERSIONS
if [ -z $AR_BRANCH ]; then
  export AR_BRANCH="2.0.17" #defaulting this to a known good version, can still be overridden
fi
if [ -z $IDF_BRANCH ]; then
  export IDF_BRANCH="release/v4.4" #defaulting this to a known good version, can still be overridden
fi
if [ -z $BLUEPAD32_BRANCH ]; then
  export BLUEPAD32_BRANCH="4.1.0" #defaulting this to a known good version, can still be overridden
fi
if [ -z $ESP_DL_VERSION ]; then
  export ESP_DL_VERSION="0632d2447dd49067faabe9761d88fa292589d5d9" #defaulting this to a known good commit, can still be overridden
fi
if [ -z $ESP32_CAMERA_VERSION ]; then
  export ESP32_CAMERA_VERSION="7aa37d4f22503fdac9ccd449e4678c4894c40055" #defaulting this to a known good version, can still be overridden
fi
if [ -z $ESP_LITTLEFS_VERSION ]; then
  export ESP_LITTLEFS_VERSION="3e5e7a11b7f06515a1f93873b6fe5a9efe88338b" #defaulting this to a known good version, can still be overridden
fi
if [ -z $ESPRESSIF_DSP_VERSION ]; then
  export ESPRESSIF_DSP_VERSION="b3841d696950b2591cd84c94a0494c724a9f322e" #defaulting this to a known good version, can still be overridden
fi
if [ -z $TINYUSB_VERSION ]; then
  export TINYUSB_VERSION="0.17.0" #defaulting this to a known good version, can still be overridden
fi
if [ -z $ESP_RAINMAKER_VERSION ]; then
  export $ESP_RAINMAKER_VERSION="f98cf1ec50bff6706c5afe626806fe9d95dbc141" #defaulting this to a known good version, can still be overridden
fi


IDF_COMPS="$IDF_PATH/components"
IDF_TOOLCHAIN="xtensa-$IDF_TARGET-elf"

# Owner of the target ESP32 Arduino repository
AR_USER="espressif"

# The full name of the repository
AR_REPO="$AR_USER/arduino-esp32"

AR_REPO_URL="https://github.com/$AR_REPO.git"
if [ -n $GITHUB_TOKEN ]; then
	AR_REPO_URL="https://$GITHUB_TOKEN@github.com/$AR_REPO.git"
fi

AR_ROOT="$PWD"
AR_COMPS="$AR_ROOT/components"
AR_OUT="$AR_ROOT/out"
AR_TOOLS="$AR_OUT/tools"
AR_PLATFORM_TXT="$AR_OUT/platform.txt"
AR_GEN_PART_PY="$AR_TOOLS/gen_esp32part.py"
AR_SDK="$AR_TOOLS/sdk/$IDF_TARGET"
if [ -z $DIST_PATH ]; then
	export DIST_PATH="$AR_ROOT/dist"
fi
if [ -z $DIST_VERSION ]; then
  export DIST_VERSION=`git branch --show-current | sed -e "s/^\(.*\/\)*v\?//g"`
fi
if [ -z $DIST_NAME ]; then
  export DIST_NAME="phasedock-esp32-robotarm-$DIST_VERSION"
fi

function get_os(){
  	OSBITS=`uname -m`
  	if [[ "$OSTYPE" == "linux"* ]]; then
        if [[ "$OSBITS" == "i686" ]]; then
        	echo "linux32"
        elif [[ "$OSBITS" == "x86_64" ]]; then
        	echo "linux64"
        elif [[ "$OSBITS" == "armv7l" ]]; then
        	echo "linux-armel"
        else
        	echo "unknown"
	    	return 1
        fi
	elif [[ "$OSTYPE" == "darwin"* ]]; then
	    echo "macos"
	elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
	    echo "win32"
	else
	    echo "$OSTYPE"
	    return 1
	fi
	return 0
}

AR_OS=`get_os`

export SED="sed"
export SSTAT="stat -c %s"

if [[ "$AR_OS" == "macos" ]]; then
	if ! [ -x "$(command -v gsed)" ]; then
		echo "ERROR: gsed is not installed! Please install gsed first. ex. brew install gsed"
		exit 1
	fi
	if ! [ -x "$(command -v gawk)" ]; then
		echo "ERROR: gawk is not installed! Please install gawk first. ex. brew install gawk"
		exit 1
	fi
	export SED="gsed"
	export SSTAT="stat -f %z"
fi

function git_commit_exists(){ #git_commit_exists <repo-path> <commit-message>
	local repo_path="$1"
	local commit_message="$2"
	local commits_found=`git -C "$repo_path" log --all --grep="$commit_message" | grep commit`
	if [ -n "$commits_found" ]; then echo 1; else echo 0; fi
}

function git_branch_exists(){ # git_branch_exists <repo-path> <branch-name>
	local repo_path="$1"
	local branch_name="$2"
	local branch_found=`git -C "$repo_path" ls-remote --heads origin "$branch_name"`
	if [ -n "$branch_found" ]; then echo 1; else echo 0; fi
}

function git_pr_exists(){ # git_pr_exists <branch-name>
	local pr_num=`curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" "https://api.github.com/repos/$AR_REPO/pulls?head=$AR_USER:$1&state=open" | jq -r '.[].number'`
	if [ ! "$pr_num" == "" ] && [ ! "$pr_num" == "null" ]; then echo 1; else echo 0; fi
}

function git_create_pr(){ # git_create_pr <branch> <title>
	local pr_branch="$1"
	local pr_title="$2"
	local pr_target="$3"
	local pr_body=""
	pr_body+="esp-idf: "$(git -C "$IDF_PATH" symbolic-ref --short HEAD || git -C "$IDF_PATH" tag --points-at HEAD)" "$(git -C "$IDF_PATH" rev-parse --short HEAD)"\r\n"
	for component in `ls "$AR_COMPS"`; do
		if [ ! $component == "arduino" ]; then
			if [ -d "$AR_COMPS/$component/.git" ] || [ -d "$AR_COMPS/$component/.github" ]; then
				pr_body+="$component: "$(git -C "$AR_COMPS/$component" symbolic-ref --short HEAD || git -C "$AR_COMPS/$component" tag --points-at HEAD)" "$(git -C "$AR_COMPS/$component" rev-parse --short HEAD)"\r\n"
			fi
		fi
	done
	pr_body+="tinyusb: "$(git -C "$AR_COMPS/arduino_tinyusb/tinyusb" symbolic-ref --short HEAD || git -C "$AR_COMPS/arduino_tinyusb/tinyusb" tag --points-at HEAD)" "$(git -C "$AR_COMPS/arduino_tinyusb/tinyusb" rev-parse --short HEAD)"\r\n"
	local pr_data="{\"title\": \"$pr_title\", \"body\": \"$pr_body\", \"head\": \"$AR_USER:$pr_branch\", \"base\": \"$pr_target\"}"
	git_create_pr_res=`echo "$pr_data" | curl -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" --data @- "https://api.github.com/repos/$AR_REPO/pulls"`
	local done_pr=`echo "$git_create_pr_res" | jq -r '.title'`
	if [ ! "$done_pr" == "" ] && [ ! "$done_pr" == "null" ]; then echo 1; else echo 0; fi
}

