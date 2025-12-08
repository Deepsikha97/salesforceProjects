@RestResource(urlMapping='/github/comments')
global without sharing class GitHubCommentCallback {

    @HttpPost
    global static void handleCallback() {
        RestRequest req = RestContext.request;
        if (req == null || req.requestBody == null) {
            return;
        }

        String body = req.requestBody.toString();
        System.debug('GitHub webhook payload: ' + body);

        // Deserialize to untyped map
        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(body);

        if (payload == null) {
            return;
        }

        // GitHub issue_comment webhook payload has "issue" and "comment"
        Map<String, Object> issueMap =
            (Map<String, Object>) payload.get('issue');
        Map<String, Object> commentMap =
            (Map<String, Object>) payload.get('comment');

        if (issueMap == null || commentMap == null) {
            System.debug('Missing issue or comment node in payload.');
            return;
        }

        // Reuse your wrapper factory to map "number" -> issueNumber
        GitHubIssueWrapper issueWrapper =
            GitHubIssueWrapper.fromRaw(issueMap);

        if (issueWrapper == null || issueWrapper.issueNumber == null) {
            System.debug('No issueNumber found on inbound payload.');
            return;
        }

        String commentBody = (String) commentMap.get('body');
        if (String.isBlank(commentBody)) {
            System.debug('Comment body is blank.');
            return;
        }

        // Find the Case based on GitHub issue number
        List<Case> relatedCases = [
            SELECT Id
            FROM Case
            WHERE GitHub_Issue_Number__c = :issueWrapper.issueNumber
            LIMIT 1
        ];

        if (relatedCases.isEmpty()) {
            System.debug('No Case found for GitHub issueNumber: ' + issueWrapper.issueNumber);
            return;
        }

        Case relatedCase = relatedCases[0];

        // Create CaseComment from GitHub comment
        CaseComment cc = new CaseComment(
            ParentId   = relatedCase.Id,
            CommentBody = commentBody,
            IsPublished = true
        );

        insert cc;

        System.debug('Created CaseComment for Case ' + relatedCase.Id);
    }
}
