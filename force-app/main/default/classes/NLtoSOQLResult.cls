public class NLtoSOQLResult {

    @InvocableVariable(label='Generated SOQL')
    public String soqlQuery;

    @InvocableVariable(label='Natural Language Summary')
    public String naturalLanguageSummary;

    @InvocableVariable(label='Is Success')
    public Boolean isSuccess;

    @InvocableVariable(label='Error Message')
    public String errorMessage;

    @InvocableVariable(label='Access Denied Fields')
    public String accessDeniedFields;
}