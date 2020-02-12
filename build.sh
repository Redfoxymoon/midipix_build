#!/bin/sh
# Copyright (c) 2016, 2017 Lucio Andrés Illanes Albornoz <lucio@lucioillanes.de>
#

buildp_dispatch() {
	local _msg="${1}" _group_name="${2}" _pkg_name="${3}"					\
		_build_group_meta="" _build_group_lc="" _build_groups_lc="" _last_pkg="" _pkg_restart="" PKGS_FOUND;
	case "${_msg}" in
	# Top-level
	start_build)	shift; build_args "${@}"; build_init;
			ex_rtl_log_set_vnfo_lvl "${ARG_VERBOSE:-0}";
			ex_rtl_log_msg info "Build started by ${BUILD_USER:=${USER}}@${BUILD_HNAME:=$(hostname)} at ${BUILD_DATE_START}.";
			ex_rtl_log_env_vars "build (global)" ${DEFAULT_LOG_ENV_VARS};
			_build_groups_lc="${BUILD_GROUPS:-${GROUPS_DEFAULT}}";
			if ! ex_rtl_lmatch "${ARG_DIST}" , rpm; then
				_build_groups_lc="$(ex_rtl_lfilter "${_build_groups_lc}" "host_tools_rpm")";
			fi;
			if [ "${ARG_RESTART}" = "LAST" ]; then
				if [ -n "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}" ]\
				&& [ -e "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}" ]; then
					_last_pkg="$(cat "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}")";
					ex_rtl_fileop rm "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}";
					ex_rtl_state_clear "${BUILD_WORKDIR}" "${_last_pkg}";
				fi;
			fi;
			PKGS_FOUND="";
			for _build_group_lc in ${_build_groups_lc}; do
				ex_pkg_dispatch "${_build_group_lc}"				\
						"${ARG_RESTART}" "${ARG_RESTART_AT}"		\
						buildp_dispatch PKGS_FOUND;
				if [ ${?} -ne 0 ]; then
					break;
				fi;
			done;
			for _pkg_restart in ${ARG_RESTART}; do
				if ! ex_rtl_lmatch "ALL LAST" " " "${_pkg_restart}"		\
				&& ! ex_rtl_lmatch "${PKGS_FOUND}" " " "${_pkg_restart}"; then
					ex_rtl_log_msg failexit "Error: package \`${_pkg_restart}' unknown.";
				fi;
			done;
			if ! ex_pkg_dispatch "invariants" "ALL" "ALL" buildp_dispatch ""; then
				break;
			fi;
			buildp_dispatch finish_build; ;;
	finish_build)	build_fini;
			ex_rtl_log_msg info "${BUILD_NFINI} finished, ${BUILD_NSKIP} skipped, and ${BUILD_NFAIL} failed builds in ${BUILD_NBUILT} build script(s).";
			ex_rtl_log_msg info "Build time: ${BUILD_TIMES_HOURS} hour(s), ${BUILD_TIMES_MINUTES} minute(s), and ${BUILD_TIMES_SECS} second(s).";
			if [ -n "${BUILD_PKGS_FAILED}" ]; then
				ex_rtl_log_msg failexit "Build script failure(s) in: ${BUILD_PKGS_FAILED}.";
			fi; ;;

	# Group build
	start_group)	ex_rtl_log_msg inf2 "Starting \`${_group_name}' build group..."; ;;
	finish_group)	ex_rtl_log_msg suc2 "Finished \`${_group_name}' build group."; ;;

	# Package build
	start_pkg)	ex_rtl_log_msg info "$(printf "[%03d/%03d] Starting \`%s' build..." "${4}" "${5}" "${_pkg_name}")"; ;;
	finish_pkg)	: $((BUILD_NFINI+=1));
			if [ "${ARG_VERBOSE:-0}" -ge 2 ]; then
				cat "${BUILD_WORKDIR}/${_pkg_name}_stderrout.log";
			fi;
			ex_rtl_log_msg succ "$(printf "Finished \`%s' build." "${_pkg_name}")"; ;;
	fail_pkg)	: $((BUILD_NFAIL+=1));
			BUILD_PKGS_FAILED="${BUILD_PKGS_FAILED:+${BUILD_PKGS_FAILED} }${_pkg_name}";
			if [ "${ARG_RELAXED:-0}" -eq 1 ]; then
				ex_rtl_log_msg fail "$(printf "Build failed in \`%s', check \`%s' for details." "${_pkg_name}" "${BUILD_WORKDIR}/${_pkg_name}_stderrout.log")";
			else
				ex_rtl_log_msg fail "${BUILD_WORKDIR}/${_pkg_name}_stderrout.log:";
				cat "${BUILD_WORKDIR}/${_pkg_name}_stderrout.log";
				if [ -n "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}" ]; then
					echo "${_pkg_name}" > "${DEFAULT_BUILD_LAST_FAILED_PKG_FNAME}";
				fi;
				ex_rtl_log_msg fail "$(printf "Build failed in \`%s'." "${_pkg_name}")";
				if [ "${ARG_PARALLEL:-0}" -eq 1 ]; then
					ex_rtl_log_msg fail "Terminating pending builds...";
					pkill -P "${$}";
				fi;
				exit 1;
			fi; ;;
	disabled_pkg)	: $((BUILD_NSKIP+=1));
			ex_rtl_log_msg vnfo "$(printf "[%03d/%03d] Skipping disabled package \`%s.'" "${4}" "${5}" "${_pkg_name}")"; ;;
	skipped_pkg)	: $((BUILD_NSKIP+=1));
			ex_rtl_log_msg vnfo "$(printf "[%03d/%03d] Skipping finished package \`%s.'" "${4}" "${5}" "${_pkg_name}")"; ;;
	step_pkg)	ex_rtl_log_msg vucc "$(printf "Finished build step %s of package \`%s'." "${4}" "${_pkg_name}")"; ;;

	# Child process
	exec_finish)	;;
	exec_missing)	ex_rtl_log_msg failexit "Error: package \`${_pkg_name}' missing in build.vars."; ;;
	exec_start)	if [ "${PKG_NO_LOG_VARS:-0}" -eq 0 ]; then
				ex_rtl_log_env_vars "build"		\
					$(set | awk -F= '/^PKG_/{print $1}' | sort);
			fi;
			if [ "${ARG_VERBOSE:-0}" -ge 3 ]; then
				set -o xtrace;
			fi; ;;
	exec_step)	ex_rtl_log_msg info "Finished build step ${4} of package \`${_pkg_name}'."; ;;
	esac; return 0;
};

for __ in $(find subr -name *.subr); do
	. "${__}"; done; buildp_dispatch start_build "${@}";

# vim:filetype=sh textwidth=0
