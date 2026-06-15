public with sharing class SOQLSecurityValidator {

    private static final Set<String> BLOCKED_KEYWORDS = new Set<String>{
        'INSERT', 'UPDATE', 'DELETE', 'UPSERT', 'MERGE', 'UNDELETE'
    };

    private static final Integer MAX_LIMIT = 200;

    public class QuerySecurityException extends Exception {}

    /**
     * Validates LLM-generated SOQL before it is returned to the user.
     * Checks:
     *   1. Query starts with SELECT (no DML permitted)
     *   2. No subqueries (Phase 1 scope boundary)
     *   3. Object is in the OLS-filtered whitelist (accessibleSchema)
     *   4. Every queried field passes the FLS check (accessibleSchema)
     *   5. LIMIT is present and does not exceed MAX_LIMIT
     *
     * @param soql              Raw SOQL string returned by the LLM
     * @param accessibleSchema  Result of SchemaContextBuilder.buildContext()
     * @return                  Sanitized SOQL string with LIMIT enforced
     * @throws QuerySecurityException if any check fails
     */
    public static String validate(String soql, Map<String, List<String>> accessibleSchema) {
        if (String.isBlank(soql)) {
            throw new QuerySecurityException(
                'The assistant returned an empty response. Please rephrase your request.'
            );
        }

        if (soql.trim().equalsIgnoreCase('UNSUPPORTED_REQUEST')) {
            throw new QuerySecurityException(
                'Your request cannot be fulfilled with a SELECT query. Please try a different request.'
            );
        }

        // Normalize: collapse all whitespace to single spaces
        String normalized = soql.trim().replaceAll('\\s+', ' ');
        String upper = normalized.toUpperCase();

        // 1. Must start with SELECT
        if (!upper.startsWith('SELECT ')) {
            throw new QuerySecurityException(
                'Only SELECT queries are permitted. The generated query was rejected for security reasons.'
            );
        }

        // 2. Block DML keywords (word-boundary checks to avoid false positives)
        for (String keyword : BLOCKED_KEYWORDS) {
            if (upper.contains(' ' + keyword + ' ') || upper.endsWith(' ' + keyword)) {
                throw new QuerySecurityException(
                    'DML operations are not permitted. Only SELECT statements are allowed.'
                );
            }
        }

        // 3. Block subqueries (Phase 1 scope boundary)
        if (upper.contains('(SELECT')) {
            throw new QuerySecurityException(
                'Subqueries are not supported. Please query one object at a time.'
            );
        }

        // 4. Extract object name from FROM clause
        String objectName = extractObjectName(upper, normalized);
        if (String.isBlank(objectName)) {
            throw new QuerySecurityException(
                'Could not identify the object in the FROM clause. Please rephrase your query.'
            );
        }

        // Case-insensitive lookup against the whitelisted schema
        String canonicalObjectName = null;
        for (String key : accessibleSchema.keySet()) {
            if (key.equalsIgnoreCase(objectName)) {
                canonicalObjectName = key;
                break;
            }
        }

        if (canonicalObjectName == null) {
            throw new QuerySecurityException(
                'You do not have permission to query "' + objectName +
                '". It is either not in the allowed list or your profile lacks read access to this object.'
            );
        }

        // 5. FLS: validate each queried field
        List<String> queryFields = extractFields(normalized, upper);
        Set<String> accessibleFieldsLower = new Set<String>();
        for (String f : accessibleSchema.get(canonicalObjectName)) {
            accessibleFieldsLower.add(f.toLowerCase());
        }

        List<String> deniedFields = new List<String>();
        for (String field : queryFields) {
            String fieldLower = field.toLowerCase();
            // Allow aggregate functions like COUNT(), COUNT(Id), MAX(Amount)
            if (fieldLower.startsWith('count(') || fieldLower.startsWith('max(') ||
                fieldLower.startsWith('min(') || fieldLower.startsWith('sum(') ||
                fieldLower.startsWith('avg(')) {
                continue;
            }
            if (!accessibleFieldsLower.contains(fieldLower)) {
                deniedFields.add(field);
            }
        }

        if (!deniedFields.isEmpty()) {
            throw new QuerySecurityException(
                'FLS restriction: You do not have access to the following field(s): ' +
                String.join(deniedFields, ', ') +
                '. Please remove them from your query.'
            );
        }

        // 6. Enforce LIMIT
        normalized = enforceLimitClause(normalized, upper);

        return normalized;
    }

    // --- Private Helpers ---

    private static String extractObjectName(String upper, String original) {
        Integer fromIdx = upper.indexOf(' FROM ');
        if (fromIdx == -1) {
            return null;
        }
        // Extract the token immediately after FROM
        String afterFrom = original.substring(fromIdx + 6).trim();
        Integer spaceIdx = afterFrom.indexOf(' ');
        return spaceIdx == -1 ? afterFrom : afterFrom.substring(0, spaceIdx);
    }

    private static List<String> extractFields(String soql, String upper) {
        Integer fromIdx = upper.indexOf(' FROM ');
        if (fromIdx == -1) {
            return new List<String>();
        }
        // Field list is everything between SELECT (inclusive) and FROM (exclusive)
        String fieldsPart = soql.substring('SELECT '.length(), fromIdx).trim();
        List<String> fields = new List<String>();
        for (String f : fieldsPart.split(',')) {
            String trimmed = f.trim();
            if (String.isNotBlank(trimmed)) {
                fields.add(trimmed);
            }
        }
        return fields;
    }

    private static String enforceLimitClause(String soql, String upper) {
        Integer limitIdx = upper.indexOf(' LIMIT ');
        if (limitIdx == -1) {
            // No LIMIT present — append the cap
            return soql + ' LIMIT ' + MAX_LIMIT;
        }

        // Extract the existing LIMIT value
        String afterLimit = soql.substring(limitIdx + 7).trim();
        Integer spaceIdx = afterLimit.indexOf(' ');
        String limitValueStr = spaceIdx == -1 ? afterLimit : afterLimit.substring(0, spaceIdx);

        try {
            Integer limitValue = Integer.valueOf(limitValueStr);
            if (limitValue > MAX_LIMIT) {
                // Cap the LIMIT at MAX_LIMIT, preserve anything after the value (e.g. OFFSET)
                String tail = spaceIdx == -1 ? '' : ' ' + afterLimit.substring(spaceIdx).trim();
                return soql.substring(0, limitIdx) + ' LIMIT ' + MAX_LIMIT + tail;
            }
        } catch (Exception e) {
            // Unparseable LIMIT — replace with safe cap
            return soql.substring(0, limitIdx) + ' LIMIT ' + MAX_LIMIT;
        }

        return soql;
    }
}