public with sharing class GitHubService {
    // Named Credential API name
    private static final String NC_NAME = 'GitHub_NC';

    // Used for GitHub's required User-Agent header
    private static final String USER_AGENT = 'Salesforce-GitHub-Integration';

    // ---------- OUTBOUND: GET ISSUE INFO ----------

    @AuraEnabled
    public static GitHubIssueWrapper getIssueInfo(Id caseId) {
        Case c = [
            SELECT Id, GitHub_Repo__c, GitHub_Issue_Number__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // If nothing linked, just return null (LWC can handle "no issue")
        if (c.GitHub_Issue_Number__c == null || String.isBlank(c.GitHub_Repo__c)) {
            return null;
        }

        String path =
            '/repos/' +
            c.GitHub_Repo__c +
            '/issues/' +
            String.valueOf(c.GitHub_Issue_Number__c);

        HttpResponse res = sendGitHubRequest('GET', path, null);

        if (res.getStatusCode() == 200) {
            System.debug('GitHub Issue Info: ' + res.getBody());

            // Deserialize into a generic map so we can manually map "number" -> issueNumber
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            GitHubIssueWrapper issueInfo = GitHubIssueWrapper.fromRaw(raw);

            return issueInfo;
        } else {
            throw new AuraHandledException(
                'Error fetching GitHub issue info: ' +
                res.getStatusCode() +
                ' ' +
                res.getBody()
            );
        }
    }

    // ---------- OUTBOUND: CREATE ISSUE FROM CASE ----------

    @AuraEnabled
    public static GitHubIssueWrapper createIssueFromCase(Id caseId) {
        Case c = [
            SELECT
                Id,
                Subject,
                Description,
                GitHub_Repo__c,
                GitHub_Issue_Number__c,
                GitHub_Issue_Url__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // Default repo if none set
        if (String.isBlank(c.GitHub_Repo__c)) {
            c.GitHub_Repo__c = 'Deepsikha97/sf-github-integration-demo'; //'yourGithubUser/sf-github-integration-demo'
        }

        String path = '/repos/' + c.GitHub_Repo__c + '/issues';

        // Build payload for GitHub issue
        GitHubIssueCreatePayload payload = new GitHubIssueCreatePayload();
        payload.title = c.Subject;
        payload.body =
            'Salesforce Case: ' +
            c.Id +
            '\n\n' +
            (c.Description == null ? '' : c.Description);

        HttpResponse res = sendGitHubRequest('POST', path, payload);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'GitHub issue creation failed: ' +
                res.getStatusCode() +
                ' ' +
                res.getBody()
            );
        }

        // Again deserialize into a Map so we can read "number"
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        GitHubIssueWrapper issueInfo = GitHubIssueWrapper.fromRaw(raw);

        // Write back to Case
        c.GitHub_Issue_Number__c = issueInfo.issueNumber;
        c.GitHub_Issue_Url__c = issueInfo.html_url;
        update c;

        // Return wrapper to LWC if needed
        return issueInfo;
    }

    // ---------- HELPER: COMMON GITHUB CALL ----------

    private static HttpResponse sendGitHubRequest(
        String method,
        String path,
        Object body
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NC_NAME + path);
        req.setMethod(method);
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('User-Agent', USER_AGENT);

        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(body));
        }

        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug(
            'GitHub response ' + res.getStatusCode() + ': ' + res.getBody()
        );
        return res;
    }
    public class GitHubIssueCreatePayload {
        public String title;
        public String body;

        public GitHubIssueCreatePayload() {}
    }
}