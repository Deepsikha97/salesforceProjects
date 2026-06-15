public with sharing class SchemaContextBuilder {

    public class ObjectNotPermittedException extends Exception {}

    /**
     * Returns the Object_API_Name__c values of all active CMT whitelist records.
     * Used to give the LLM a lightweight list of queryable object names.
     *
     * @return List of object API names permitted for querying
     */
    public static List<String> getWhitelistedObjectNames() {
        List<String> names = new List<String>();
        for (Queryable_Object__mdt cmtRecord : [
            SELECT Object_API_Name__c
            FROM Queryable_Object__mdt
            WHERE Is_Active__c = true
        ]) {
            names.add(cmtRecord.Object_API_Name__c);
        }
        return names;
    }

    /**
     * Validates a single object against the CMT whitelist, then applies OLS and FLS
     * checks for the running user to return only permitted fields for that object.
     *
     * Throws ObjectNotPermittedException if:
     *   - objectApiName is not an active record in Queryable_Object__mdt
     *   - objectApiName does not exist in the org schema
     *   - The running user lacks OLS read access to the object
     *
     * @param objectApiName  The Salesforce object API name to validate and describe
     * @return Map of objectApiName -> List of accessible field API names (single entry)
     */
    public static Map<String, List<String>> buildContext(String objectApiName) {
        Map<String, List<String>> result = new Map<String, List<String>>();

        if (String.isBlank(objectApiName)) {
            throw new ObjectNotPermittedException('Object API name cannot be blank.');
        }

        // CMT whitelist check — single targeted query
        List<Queryable_Object__mdt> cmtMatches = [
            SELECT Object_API_Name__c
            FROM Queryable_Object__mdt
            WHERE Object_API_Name__c = :objectApiName
            AND Is_Active__c = true
            LIMIT 1
        ];

        if (cmtMatches.isEmpty()) {
            throw new ObjectNotPermittedException(
                '"' + objectApiName + '" is not in the list of permitted queryable objects. ' +
                'Contact your administrator to enable it.'
            );
        }

        // Describe only this object — avoids heap cost of getGlobalDescribe()
        Schema.DescribeSObjectResult objDescribe;
        try {
            objDescribe = Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (Exception e) {
            throw new ObjectNotPermittedException(
                '"' + objectApiName + '" does not exist in this org\'s schema.'
            );
        }

        // OLS check: running user must have Read access
        if (!objDescribe.isAccessible()) {
            throw new ObjectNotPermittedException(
                'Your profile does not have read access to "' + objectApiName + '".'
            );
        }

        // FLS check via Security.stripInaccessible — single native platform call
        // instead of calling getDescribe() per field inside a loop (CPU-expensive).
        //
        // Approach:
        //   1. Get all field names from the map keys (no describe calls — just key access)
        //   2. Populate a prototype SObject with every field set to null so the
        //      platform knows which fields to evaluate for FLS
        //   3. stripInaccessible removes fields the running user cannot read and
        //      records exactly which ones were removed via getRemovedFields()
        //   4. Accessible fields = all fields minus the removed set
        Map<String, Schema.SObjectField> fieldsMap = objDescribe.fields.getMap();

        SObject prototype = objDescribe.getSObjectType().newSObject();
        for (String fieldName : fieldsMap.keySet()) {
            try {
                prototype.put(fieldName, null);
            } catch (SObjectException e) {
                // Compound/read-only system fields (e.g. BillingAddress) cannot be
                // set directly — skip them; their component fields are still evaluated.
            }
        }

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE,
            new List<SObject>{ prototype }
        );

        Set<String> removedFields = decision.getRemovedFields().get(objectApiName);
        if (removedFields == null) {
            removedFields = new Set<String>();
        }

        List<String> accessibleFields = new List<String>();
        for (String fieldName : fieldsMap.keySet()) {
            if (!removedFields.contains(fieldName)) {
                // String.valueOf on an SObjectField token returns the properly-cased
                // API name (e.g. "AccountId") without calling getDescribe()
                accessibleFields.add(String.valueOf(fieldsMap.get(fieldName)));
            }
        }

        result.put(objectApiName, accessibleFields);
        return result;
    }

    /**
     * Serializes the OLS/FLS-filtered schema map to a compact JSON string
     * suitable for injection into an Einstein Prompt Template input.
     *
     * @param context  Result of buildContext()
     * @return Compact JSON string
     */
    public static String buildContextAsJSON(Map<String, List<String>> context) {
        return JSON.serialize(context);
    }
}