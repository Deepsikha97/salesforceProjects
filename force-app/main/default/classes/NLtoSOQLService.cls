public with sharing class NLtoSOQLService {

    // Must match the API Name of the Prompt Template in Setup > Prompt Builder
    private static final String PROMPT_TEMPLATE_NAME = 'NLtoSOQLPromptTemplate';

    /**
     * Converts a natural language query into a validated SOQL SELECT statement.
     *
     * Flow:
     *   1. Fetch whitelisted object names from CMT (lightweight — no describe calls)
     *   2. Invoke the Einstein Prompt Template with the NL query + object name list
     *   3. Extract the target object name from the raw SOQL returned by the LLM
     *   4. Call SchemaContextBuilder.buildContext(objectName) — CMT whitelist check,
     *      OLS, and FLS for that specific object only
     *   5. Validate the full SOQL (SELECT-only, field FLS, LIMIT cap)
     *   6. Return NLtoSOQLResult with the validated SOQL or a descriptive error
     *
     * @param naturalLanguageQuery  Plain English description of the data to retrieve
     * @return NLtoSOQLResult       Contains soqlQuery on success or errorMessage on failure
     */
    public static NLtoSOQLResult generateSOQL(String naturalLanguageQuery) {
        NLtoSOQLResult result = new NLtoSOQLResult();

        if (String.isBlank(naturalLanguageQuery)) {
            result.isSuccess = false;
            result.errorMessage = 'Please enter a query description.';
            return result;
        }

        try {
            // Step 1: Get whitelisted object names only — no describe calls yet
            List<String> whitelistedObjects = SchemaContextBuilder.getWhitelistedObjectNames();

            if (whitelistedObjects.isEmpty()) {
                result.isSuccess = false;
                result.errorMessage = 'No queryable objects are configured. Contact your administrator.';
                return result;
            }

            // Step 2: Build prompt inputs — pass object names as context for the LLM
            ConnectApi.WrappedValue userQueryValue = new ConnectApi.WrappedValue();
            userQueryValue.value = naturalLanguageQuery;

            ConnectApi.WrappedValue queryableObjectsValue = new ConnectApi.WrappedValue();
            queryableObjectsValue.value = String.join(whitelistedObjects, ', ');

            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            inputParams.put('Input:User_Query', userQueryValue);
            inputParams.put('Input:Queryable_Objects', queryableObjectsValue);

            // Step 3: Call Einstein LLM via PromptUtils
            String rawSOQL = PromptUtils.invokePrompt(PROMPT_TEMPLATE_NAME, inputParams);

            // Step 4: Extract the object name from the raw SOQL
            String objectName = extractObjectNameFromSOQL(rawSOQL);
            if (String.isBlank(objectName)) {
                result.isSuccess = false;
                result.errorMessage = 'Could not identify the object in the generated query. Please rephrase your request.';
                return result;
            }

            // Step 5: CMT whitelist check + OLS + FLS — targeted to just this object.
            // Throws SchemaContextBuilder.ObjectNotPermittedException if the object is
            // not whitelisted or the running user lacks OLS read access.
            Map<String, List<String>> accessibleSchema = SchemaContextBuilder.buildContext(objectName);

            // Step 6: Security validation — rejects DML, verifies FLS, caps LIMIT
            String validatedSOQL = SOQLSecurityValidator.validate(rawSOQL, accessibleSchema);

            result.isSuccess = true;
            result.soqlQuery = validatedSOQL;
            result.naturalLanguageSummary = naturalLanguageQuery;

        } catch (SchemaContextBuilder.ObjectNotPermittedException e) {
            result.isSuccess = false;
            result.errorMessage = e.getMessage();
        } catch (SOQLSecurityValidator.QuerySecurityException e) {
            result.isSuccess = false;
            result.errorMessage = e.getMessage();
        } catch (Exception e) {
            result.isSuccess = false;
            result.errorMessage = 'An error occurred while generating the SOQL query: ' + e.getMessage();
        }

        return result;
    }

    // Extracts the object API name from the token immediately after FROM
    private static String extractObjectNameFromSOQL(String soql) {
        if (String.isBlank(soql)) {
            return null;
        }
        String upper = soql.trim().replaceAll('\\s+', ' ').toUpperCase();
        Integer fromIdx = upper.indexOf(' FROM ');
        if (fromIdx == -1) {
            return null;
        }
        String afterFrom = soql.substring(fromIdx + 6).trim();
        Integer spaceIdx = afterFrom.indexOf(' ');
        return spaceIdx == -1 ? afterFrom : afterFrom.substring(0, spaceIdx);
    }
}