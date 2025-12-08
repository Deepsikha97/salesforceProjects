import { LightningElement, api } from "lwc";
import getIssueInfo from "@salesforce/apex/GitHubService.getIssueInfo";
import createIssueFromCase from "@salesforce/apex/GitHubService.createIssueFromCase";

export default class GithubIssuePanel extends LightningElement {
    // backing field
    _recordId;

    issueLinked ;
    issueUrl;
    issueTitle;
    issueNumber;
    issueState;
    error = null;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        console.log("recordId set from ScreenAction => ", value);

        // Only call once we actually have an Id
        if (value) {
            this.loadIssue();
        }
    }

    handleCreate() {
        this.error = null;
        createIssueFromCase({ caseId: this.recordId })
            .then(() => {
                console.log("Issue created successfully");
                this.loadIssue();
            })
            .catch((err) => {
                console.error("Error creating issue:", err);
                this.error = err;
            });
    }

    handleRefresh() {
        this.loadIssue();
    }

    loadIssue() {
        this.error = null;
        console.log("Calling getIssueInfo with caseId => ", this.recordId);

        if (!this.recordId) {
            console.warn("recordId not set yet, skipping loadIssue");
            return;
        }

        getIssueInfo({ caseId: this.recordId })
            .then((result) => {
                console.log("getIssueInfo result => ", JSON.stringify(result));

                if (result && result.issueNumber) {
                    this.issueLinked = true;
                    this.issueNumber = result.issueNumber;
                    this.issueTitle = result.title;
                    this.issueState = result.state;
                    this.issueUrl = result.html_url;
                } else {
                    this.issueLinked = false;
                }
            })
            .catch((err) => {
                console.error("Error in getIssueInfo:", err);
                this.issueLinked = false;
                this.error = err;
            });
    }
}