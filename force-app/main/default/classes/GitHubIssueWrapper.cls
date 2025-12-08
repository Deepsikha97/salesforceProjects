// ---------- WRAPPER CLASS ----------

    public class GitHubIssueWrapper {
        @AuraEnabled
        public String title;
        @AuraEnabled
        public Integer issueNumber;
        @AuraEnabled
        public String state;
        @AuraEnabled
        public String html_url;

        public GitHubIssueWrapper() {}

        // Factory method to map from raw JSON map (with "number") to issueNumber
        public static GitHubIssueWrapper fromRaw(Map<String, Object> raw) {
            GitHubIssueWrapper w = new GitHubIssueWrapper();

            w.title = (String) raw.get('title');
            w.state = (String) raw.get('state');
            w.html_url = (String) raw.get('html_url');

            Object numVal = raw.get('number');
            if (numVal != null) {
                if (numVal instanceof Integer) {
                    w.issueNumber = (Integer) numVal;
                } else {
                    w.issueNumber = Integer.valueOf(String.valueOf(numVal));
                }
            }

            return w;
        }
    }