import { LightningElement, track, wire, api } from "lwc";
import generateArticleDraft from "@salesforce/apex/KnowledgeArticleController.generateArticleDraft";
import saveArticle from "@salesforce/apex/KnowledgeArticleController.saveArticle";
import mergeArticles from "@salesforce/apex/KnowledgeArticleController.mergeArticles";
import mergeIntoExistingArticle from "@salesforce/apex/KnowledgeArticleController.mergeIntoExistingArticle";

import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class KnowledgeDraftGenerator extends LightningElement {
	isModalOpen = false;
	isLoading = false;
	@track draftArticle = {};
	@track duplicateArticles = [];
	@api recordId;
	draftArticleCreated = false;
	duplicateArticlesFound = false;
	allowMerge = false;

	handleGenerate() {
		this.isModalOpen = true;
		this.isLoading = true;

		generateArticleDraft({ caseId: this.recordId })
			.then((result) => {
				// Map Apex fields correctly
				console.log("Generated Draft:", result);
				this.draftArticleCreated = true;
				this.draftArticle = {
					title: result.title,
					body: result.body
				};
				this.duplicateArticles = result.duplicates;
				this.duplicateArticlesFound = result.isDuplicateFound;
			})
			.catch((error) => {
				this.draftArticleCreated = false;
				this.duplicateArticlesFound = false;
				console.error("Error generating article draft:", error);
			})
			.finally(() => {
				this.isLoading = false;
			});
	}

	closeModal() {
		this.isModalOpen = false;
		this.draftArticle = null;
		this.duplicateArticles = [];
		this.duplicateArticlesFound = false;
		this.allowMerge = false;
	}

	handleTitleChange(event) {
		this.draftArticle.title = event.target.value;
	}

	handleBodyChange(event) {
		this.draftArticle.body = event.target.value;
	}

	handleMerge() {
		// Handle merge logic
		this.allowMerge = true;
		console.log(
			"check the value of duplicateArticlesFound:",
			this.duplicateArticlesFound
		);
		console.log("Merge button clicked" + this.duplicateArticlesFound);
		if (this.duplicateArticlesFound) {
			console.log("Merging articles");
			let duplicateArticle = this.duplicateArticles[0]; // Get the first duplicate article
			this.duplicateArticleId = duplicateArticle.articleId;
			this.isLoading = true;
			// Implement merge logic here
			mergeArticles({
				draftTitle: this.draftArticle.title,
				draftBody: this.draftArticle.body,
				existingTitle: duplicateArticle.title,
				existingBody: duplicateArticle.body
			})
				.then((result) => {
					console.log("Articles merged:", result);
					this.draftArticle.title = result.title;
					this.draftArticle.body = result.body;
					this.duplicateArticlesFound = false; // Assume merge resolves duplicates
					this.duplicateArticles = [];
				})
				.catch((error) => {
					console.error("Error merging articles:", error);
				})
				.finally(() => {
					this.isLoading = false;
				});
		}
	}

	handleSave(event) {
		// Handle save logic
		this.isLoading = true;
		console.log("save button clicked");
		console.log("merge status::" + this.allowMerge);
		if (!this.allowMerge) {
			saveArticle({
				title: this.draftArticle.title,
				body: this.draftArticle.body,
				caseId: this.recordId
			})
				.then(() => {
					console.log("Article saved successfully");
					this.closeModal();
					// Optionally show a success message
					this.dispatchEvent(
						new ShowToastEvent({
							title: "Success",
							message: "Article saved successfully",
							variant: "success"
						})
					);
				})
				.catch((error) => {
					console.error("Error saving article:", error);
					this.dispatchEvent(
						new ShowToastEvent({
							title: "Error",
							message: "Error saving article",
							variant: "error"
						})
					);
				})
				.finally(() => {
					this.isLoading = false;
				});
		} else {
			console.log("merging starts" + this.duplicateArticleId);
			try {
				mergeIntoExistingArticle({
					draftTitle: this.draftArticle.title,
					draftBody: this.draftArticle.body,
					existingArticleVersionId: this.duplicateArticleId
				})
					.then(() => {
						this.closeModal();
						// Optionally show a success message
						this.dispatchEvent(
							new ShowToastEvent({
								title: "Success",
								message: "Article merged successfully",
								variant: "success"
							})
						);
					})
					.catch((error) => {
						console.error("Error merging article:", error);
						this.dispatchEvent(
							new ShowToastEvent({
								title: "Error",
								message: "Error merging article",
								variant: "error"
							})
						);
					})
					.finally(() => {
						this.isLoading = false;
					});
			} catch (error) {
				console.log("error in merging::" + error);
			}
		}
	}
}