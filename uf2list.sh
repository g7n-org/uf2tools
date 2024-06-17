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
	outset=0
	blockNo=1
	numBlocks=99999999
	[ "${DEBUG}" = "true" ] && echo "[block ${blockNo}] initial offset: ${offset}" 1>&2
	[ "${DEBUG}" = "true" ] && echo "--------------------------------------"       1>&2
	[ "${SAVE}"  = "true" ] && echo -n                                  >  ${file}.bin

	####################################################################################
	##
	## While there are still blocks to process, keep going.
	##
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
		## Initialize block variables
		##
		ODFLAGS="-Ax -tx1z -v -w4 --endian=little"
		ZERO=0

		################################################################################
		##
		## Load the current 512-byte block into the BYTES array
		##
		BYTES=($(od ${ODFLAGS} -j ${offset} -N 512 ${file} | cut -d' ' -f2-5 | head -128))

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

				########################################################################
				##
				## The payload is 476 bytes
				##
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
				## Category-specific processing: blockNo; add one for intuitive output
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
					[ "${DEBUG}" = "true" ] && echo "${BLOCKDATA[${category}]}" > data.${blockNo}
					for byte in ${BLOCKDATA[${category}]}; do

						################################################################
						##
						## If displaying, wrap the line every 16 bytes
						##
						##
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

						################################################################
						##
						## If saving, escape each byte for hex representation, and
						## append to the .bin file. Do this up to the payloadSize.
						##
						if [ "${SAVE}"  = "true" ]; then
							if [ "${count}" -lt "${payloadSize}" ]; then
							#	if [ "${blockNo}" -eq 106 ]; then
									#echo "[payload ${payloadSize}] at count ${count}, saving ${byte} to file"
									# instead of writing directly, write to a temporary file, keeping track of sequential zeros. If the file ends and all we have are zeros, do not write them. That seems to be what is happening.
							#	fi
							    if [ "${byte}" = "00" ]; then
									let ZERO=ZERO+1
								else
									ZERO=0
								fi
								echo -ne "\\x${byte}"                   >> ${file}.bin
								let outset=outset+1
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

	####################################################################################
	##
	## File is complete, check if we have a run of trailing zeros, eliminate them
	##
	if [ "${SAVE}" = "true" ]; then
		if [ "${ZERO}" -gt 0 ]; then
			let cutsize=outset-ZERO
			/bin/mv -f ${file}.bin ${file}.tmp
			dd if=${file}.tmp of=${file}.bin bs=1 count=${cutsize}
			/bin/rm -f ${file}.tmp
		fi
	fi
done

exit 0
