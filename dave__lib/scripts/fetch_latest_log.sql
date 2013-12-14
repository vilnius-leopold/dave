SELECT
	*
FROM
	scheme_change_log
ORDER BY
	major_release_number DESC,
	minor_release_number DESC,
	point_release_number DESC
LIMIT 1