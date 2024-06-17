#!/usr/bin/env bash
##
## uf2list.sh - script to display contents of UF2 image
##
##       usage: uf2list.sh [OPTION..] FILE..
##
##    option - description
##   =======   =====================================================================
##     debug   display debugging information while processing (to STDERR)
##   extract   only save to file, do not perform listing display
##     quiet   silence output
##      save   extract the data sections and store them concatenated in a bin file
## 
########################################################################################

########################################################################################
##
## struct UF2_Block {
##  // 32 byte header
##  uint32_t magicStart0;
##  uint32_t magicStart1;
##  uint32_t flags;
##  uint32_t targetAddr;
##  uint32_t payloadSize;
##  uint32_t blockNo;
##  uint32_t numBlocks;
##  uint32_t fileSize; // or familyID;
##  uint8_t data[476];
##  uint32_t magicEnd;
## };
##
########################################################################################

########################################################################################
##
## Declare variables
##
CATEGORY_LIST="magicStart0 magicStart1 flags targetAddr payloadSize blockNo numBlocks"
CATEGORY_LIST="${CATEGORY_LIST} fileSize data magicEnd"
ARGS="${*}"
DEBUG=$(echo   "${ARGS}" | egrep -qio '\<debug\>'   && echo "true"  || echo "false")
SAVE=$(echo    "${ARGS}" | egrep -qio '\<save\>'    && echo "true"  || echo "false")
DISPLAY=$(echo "${ARGS}" | egrep -qio '\<quiet\>'   && echo "false" || echo "true")
EXTRACT=$(echo "${ARGS}" | egrep -qio '\<extract\>' && echo "true"  || echo "false")
ARGS=$(echo    "${ARGS}" | sed 's/debug//g'   | sed 's/  / /g')
ARGS=$(echo    "${ARGS}" | sed 's/extract//g' | sed 's/  / /g')
ARGS=$(echo    "${ARGS}" | sed 's/quiet//g'   | sed 's/  / /g')
ARGS=$(echo    "${ARGS}" | sed 's/save//g'    | sed 's/  / /g')
declare -A BLOCKDATA
declare -a BYTES

[ "${EXTRACT}" = "true" ] && DISPLAY="false" && SAVE="true"

########################################################################################
##
## Process for each file specified
##
for file in ${ARGS}; do

	####################################################################################
	##
	## Initialize per-file variables
	##
	offset=0
	blockNo=1
	numBlocks=99999999
	[ "${DEBUG}" = "true" ] && echo "[block ${blockNo}] initial offset: ${offset}" 1>&2
	[ "${DEBUG}" = "true" ] && echo "--------------------------------------"       1>&2
	[ "${SAVE}"  = "true" ] && echo -n                                  >  ${file}.bin

	while [ "${blockNo}" -le "${numBlocks}" ]; do

		################################################################################
		##
		## Display results, starting with file name
		##
		if [ "${DISPLAY}" = "true" ]; then
			echo "================================================================"
			echo "[${file}]:"
			echo "----------------------------------------------------------------"
		fi

		################################################################################
		##
		## Load the current 512-byte block into the BLOCK array
		##
		ODFLAGS="-Ax -tx1z -v -w4 --endian=little"
		BYTES=($(od ${ODFLAGS} -j ${offset} -N 512 ${file} | cut -d' ' -f2-5 | head -128))

		################################################################################
		##
		## Read and process 32 byte header; array-ize and store in DATA
		##
		#HEADER=($(od ${ODFLAGS} ${file} -j ${offset} -N 32 | cut -d' ' -f2 | head -8))

		################################################################################
		##
		## The UF2 header constitutes the first 32 bytes of the UF2 block. Determine
		## various block properties.
		##
		index=0
		for category in ${CATEGORY_LIST}; do

			############################################################################
			##
			## All categories are 4 bytes, save for "data", which is 476.
			##
			if [ "${category}" = "data" ]; then
				max=476

				########################################################################
				##
				## Break the section bytes out into individual bytes for display
				##
				value=
				for ((count=0; count<${max}; count++)); do
					value="${value} ${BYTES[$((${index}+${count}))]}"
				done
				value=$(echo "${value}" | sed 's/^  *//g' | tr 'abcdef' 'ABCDEF')
				[ "${DEBUG}" = "true" ] && echo "${value}"          >  data.${blockNo}
			else
				max=4

				########################################################################
				##
				## Break the section bytes out into individual bytes for display
				##
				value=
				for ((count=${max}-1; count>=0; count--)); do
					value="${value} ${BYTES[$((${index}+${count}))]}"
				done
				value=$(echo "${value}" | sed 's/^  *//g' | tr 'abcdef' 'ABCDEF')
				data=$(echo "${value}" | tr -d ' ')

				########################################################################
				##
				## Category-specific processing: magicStart0
				##
				if [ "${category}" = "magicStart0" ]; then
					data=$(echo "${value}"    | sed 's/\([^ ][^ ]\)/\\x\1/g')
					data=$(echo -ne "${data}" | tr -d ' \n' | rev)
					value="${value} \"${data}\""
				fi

				########################################################################
				##
				## Category-specific processing: blockNo
				##
				if [ "${category}" = "blockNo" ]; then
					blockNo=$(echo "ibase=16; ${data}+1" | bc -q)
					value="${value} (${blockNo})"
				fi

				########################################################################
				##
				## Category-specific processing: numBlocks
				##
				if [ "${category}" = "numBlocks" ]; then
					numBlocks=$(echo "ibase=16; ${data}" | bc -q)
					value="${value} (${numBlocks})"
				fi

				########################################################################
				##
				## If current category is 'payloadSize', compute that value
				##
				if [ "${category}" = "payloadSize" ]; then
					payloadSize=$(echo "ibase=16; ${data}" | bc -q)
					value="${value} (${payloadSize})"
				fi
			fi

			let index=index+max
			BLOCKDATA["${category}"]="${value}"

			############################################################################
			##
			## Display category data
			##
			if [ "${category}" = "data" ]; then
					msg="data:"
					count=0
					step=1
					value=
					for byte in ${BLOCKDATA[${category}]}; do
						if [ "${DISPLAY}" = "true" ]; then
							value="${value} ${byte}"
							if [ "${step}" -eq 16 ]; then
								value=$(echo "${value}" | sed 's/^  *//g')
								printf "    %12s %s\n" "${msg}" "${value}"
								msg=
								value=
								step=0
							fi
						fi

						if [ "${SAVE}"  = "true" ]; then
							if [ "${count}" -lt "${payloadSize}" ]; then
								echo -ne "\\x${byte}"                   >> ${file}.bin
							fi
						fi

						let count=count+1
						let step=step+1
					done
			else

				########################################################################
				##
				## Display current CATEGORY and its value
				##
				if [ "${DISPLAY}" = "true" ]; then
					printf "    %11s: %8s\n" "${category}" "${BLOCKDATA[${category}]}"
				fi
			fi
		done
		[ "${DEBUG}" = "true" ] && echo "[block ${blockNo}] starting offset: ${offset}" 1>&2

		if [ "${DEBUG}" = "true" ]; then
			echo "endMagic offset: ${offset}" 1>&2
			echo "----------------------------------------------------------------" 1>&2
		fi

		if [ "${DISPLAY}" = "true" ]; then
			echo "----------------------------------------------------------------"
			printf "block %4s / %4s (press ENTER)\n" "${blockNo}" "${numBlocks}"
			echo "================================================================"
			read
			clear
		fi
		let blockNo=blockNo+1
		let offset=offset+512
	done

done

exit 0
