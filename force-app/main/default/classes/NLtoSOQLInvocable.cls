public with sharing class NLtoSOQLInvocable {

    @InvocableMethod(
        label='Generate SOQL from Natural Language'
        description='Converts a natural language query into a SOQL SELECT statement. Respects the running user\'s Object-Level Security (OLS) and Field-Level Security (FLS). Only SELECT queries are generated — no DML is permitted.'
        category='Query Assistant'
    )
    public static List<NLtoSOQLResult> generateSOQL(List<Request> requests) {
        List<NLtoSOQLResult> responses = new List<NLtoSOQLResult>();

        Request input = requests[0];
        NLtoSOQLResult result = NLtoSOQLService.generateSOQL(input.naturalLanguageQuery);
        responses.add(result);

        return responses;
    }

    public class Request {
        @InvocableVariable(
            label='Natural Language Query'
            description='A plain English description of the data you want to retrieve, e.g. "Show me all open Cases from this year".'
            required=true
        )
        public String naturalLanguageQuery;
    }
}