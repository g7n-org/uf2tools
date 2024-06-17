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
CATEGORY=(magicStart0 magicStart1 flags targetAddr payloadSize blockNo numBlocks fileSize)
ARGLIST="${*}"
DEBUG=$(echo   "${ARGLIST}" | egrep -qio '\<debug\>'   && echo "true"  || echo "false")
SAVE=$(echo    "${ARGLIST}" | egrep -qio '\<save\>'    && echo "true"  || echo "false")
DISPLAY=$(echo "${ARGLIST}" | egrep -qio '\<quiet\>'   && echo "false" || echo "true")
EXTRACT=$(echo "${ARGLIST}" | egrep -qio '\<extract\>' && echo "true"  || echo "false")
ARGLIST=$(echo "${ARGLIST}" | sed 's/debug//g'   | sed 's/  / /g')
ARGLIST=$(echo "${ARGLIST}" | sed 's/extract//g' | sed 's/  / /g')
ARGLIST=$(echo "${ARGLIST}" | sed 's/quiet//g'   | sed 's/  / /g')
ARGLIST=$(echo "${ARGLIST}" | sed 's/save//g'    | sed 's/  / /g')
declare -a HEADER

[ "${EXTRACT}" = "true" ] && DISPLAY="false" && SAVE="true"

########################################################################################
##
## Process for each file specified
##
for file in ${ARGLIST}; do

	####################################################################################
	##
	## Initialize per-file variables
	##
	ODFLAGS="-Ax -tx4z -v -w4 --endian=little"
	offset=0
	blockNo=1
	numBlocks=99999999
	[ "${DEBUG}" = "true" ] && echo "[block ${blockNo}] initial offset: ${offset}" 1>&2
	[ "${DEBUG}" = "true" ] && echo "--------------------------------------"       1>&2
	[ "${SAVE}" = "true" ] && echo -n                                   >  ${file}.out

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
		## Read and process 32 byte header; array-ize and store in DATA
		##
		HEADER=($(od ${ODFLAGS} ${file} -j ${offset} -N 32 | cut -d' ' -f2 | head -8))
		[ "${DEBUG}" = "true" ] && echo "[block ${blockNo}] starting offset: ${offset}" 1>&2

		################################################################################
		##
		## Cycle through each of the UF2 header categories in the CATEGORY array, 
		## indexed with the DATA array
		##
		for ((index=0; index<8; index++)); do

			############################################################################
			##
			## Break the 4 bytes out into individual bytes for display
			##
			value=$(echo "${HEADER[${index}]}" | sed 's/^\(..\)\(..\)\(..\)\(..\)$/\1 \2 \3 \4/g')

			############################################################################
			##
			## Display current CATEGORY and its value
			##
			if [ "${DISPLAY}" = "true" ]; then
				printf "    %11s: %8s\n" "${CATEGORY[${index}]}" "${value}"
			fi
			if [ "${CATEGORY[${index}]}" = "numBlocks" ]; then
				value=$(echo "${HEADER[${index}]}" | tr 'a-f' 'A-F')
				numBlocks=$(echo "ibase=16; ${value}" | bc -q)
			fi
		done

		################################################################################
		##
		## Now at the data section, advance offset and prepare to read the whole 
		## section at once.
		##
		let offset=offset+32
		[ "${DEBUG}" = "true" ] && echo "header offset: ${offset}" 1>&2
		ODFLAGS="-Ax -tx4 -v --endian=little -w16"
		DATA=$(od ${ODFLAGS} -j ${offset} -N 476 ${file} | cut -d' ' -f2- | head -30 | tr -d ' ' | tr '\n' ' ')
		[ "${SAVE}" = "true" ] && echo "${DATA}" >> ${file}.out
		[ "${DEBUG}" = "true" ] && echo "${DATA}"                      >  data.${blockNo}
		msg="data:"
		for entry in ${DATA}; do
			value=$(echo "${entry}" | sed 's/\([^ ][^ ]\)/\1 /g' | sed 's/  / /g')
			if [ "${DISPLAY}" = "true" ]; then
				printf "    %12s %s\n" "${msg}" "${value}"
			fi
			msg=
		done

		####################################################################################
		##
		## Finish off with the magicEnd section
		##
		let offset=offset+476
		[ "${DEBUG}" = "true" ] && echo "data offset: ${offset}" 1>&2
		ODFLAGS="-Ax -tx4 -v --endian=little -w4"
		DATA=$(od ${ODFLAGS} ${file} -j ${offset} -N 4 | cut -d' ' -f2 | head -1)
		value=$(echo "${DATA}" | sed 's/\([^ ][^ ]\)/\1 /g' | sed 's/  / /g')
		if [ "${DISPLAY}" = "true" ]; then
			printf "    %11s: %8s\n" "endMagic" "${value}"
		fi

		let offset=offset+4
		[ "${DEBUG}" = "true" ] && echo "endMagic offset: ${offset}" 1>&2
		[ "${DEBUG}" = "true" ] && echo "----------------------------------------------------------------" 1>&2
		if [ "${DISPLAY}" = "true" ]; then
			echo "----------------------------------------------------------------"
			printf "block %4s / %4s (press ENTER)\n" "${blockNo}" "${numBlocks}"
			echo "================================================================"
			read
			clear
		fi
		let blockNo=blockNo+1
	done

	if [ "${SAVE}" = "true" ]; then
		cat ${file}.out | tr -d ' ' | tr -d '\n' >  ${file}.tmp
		echo -e "$(cat ${file}.tmp  | sed 's/\([0-9a-f][0-9a-f]\)\([0-9a-f][0-9a-f]\)\([0-9a-f][0-9a-f]\)\([0-9a-f][0-9a-f]\)/\\x\4\\x\3\\x\2\\x\1/g')" >  ${file}.bin
	fi
done

exit 0
