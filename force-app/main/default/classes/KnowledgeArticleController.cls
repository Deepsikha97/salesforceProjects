public with sharing class KnowledgeArticleController {
	@AuraEnabled(cacheable=false)
	public static DraftResult generateArticleDraft(String caseId) {
		// ====== STEP 1: Fetch Case ======
		Case caseRecord = [
			SELECT Id, Subject, Description, Status, Priority, Type, Resolution__c
			FROM Case
			WHERE Id = :caseId
			LIMIT 1
		];

		// ====== STEP 2: Prepare Prompt Input Variables ======
		ConnectApi.WrappedValue inputValueMapSubject = new ConnectApi.WrappedValue();
		inputValueMapSubject.value = caseRecord.Subject;

		ConnectApi.WrappedValue inputValueMapDescription = new ConnectApi.WrappedValue();
		inputValueMapDescription.value = caseRecord.Description;

		ConnectApi.WrappedValue inputValueMapResolution = new ConnectApi.WrappedValue();
		inputValueMapResolution.value = caseRecord.Resolution__c;

		Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
		inputParams.put('Input:caseSubject', inputValueMapSubject);
		inputParams.put('Input:caseDescription', inputValueMapDescription);
		inputParams.put('Input:caseResolution', inputValueMapResolution);

		// ====== STEP 3: Call PromptUtils ======
		String responseJson = PromptUtils.invokePrompt(
			'KnowledgeArticleDraftGenerator',
			inputParams
		);
		System.debug('Response JSON from prompt template: ' + responseJson);

		DraftResult draftResult = (DraftResult) JSON.deserialize(
			responseJson,
			DraftResult.class
		);
		draftResult.duplicates = new List<DuplicateArticle>();
		// ====== STEP 4: Find possible duplicates using Utility class ======
		String searchTitle = (draftResult.title != null
			? draftResult.title + ' '
			: '');
		system.debug('searchTitle:::' + searchTitle);

		if (String.isNotBlank(searchTitle)) {
			List<String> searchList = KnowledgeArticleDuplicateUtils.checkSemanticDuplicates(
				searchTitle,
				draftResult.body,
				50
			);

			if (!searchList.isEmpty()) {
				system.debug(' the article id from searchlist::' + searchList[0]);
				draftResult.isDuplicateFound = true;
				Knowledge__kav dupArticleRecord = [
					SELECT Id, Article_Body__c, Title
					FROM Knowledge__kav
					WHERE Id = :searchList[0]
					LIMIT 1
				];
				DuplicateArticle dup = new DuplicateArticle();
				dup.articleId = dupArticleRecord.Id;
				dup.title = dupArticleRecord.Title;
				dup.body = dupArticleRecord.Article_Body__c;
				draftResult.duplicates.add(dup);
			} else {
				draftResult.isDuplicateFound = false;
			}
		} else {
			draftResult.isDuplicateFound = false;
		}

		return draftResult;
	}

	@AuraEnabled(cacheable=false)
	public static void saveArticle(String title, String body, Id caseId) {
		// Create a new draft article (Knowledge__kav or standard KnowledgeArticleVersion depending on your org)
		Knowledge__kav article = new Knowledge__kav();
		article.Title = title;
		article.Article_Body__c = body;
		article.Language = 'en_US'; // required
		//article.PublishStatus = 'Draft'; // keep it in Draft until published
		// Generate URL-friendly name
		String safeUrlName = title != null
			? title.replaceAll('[^a-zA-Z0-9]', '-').toLowerCase()
			: 'article-' + System.currentTimeMillis();

		article.UrlName = safeUrlName;
		insert article;

		// Re-query to get master Id (ka0…)
		article = [
			SELECT Id, KnowledgeArticleId
			FROM Knowledge__kav
			WHERE Id = :article.Id
		];

		// Optionally link article to Case (if you want relationship)
		if (caseId != null) {
			CaseArticle ca = new CaseArticle();
			ca.CaseId = caseId;
			ca.KnowledgeArticleId = article.KnowledgeArticleId;
			insert ca;
		}
	}

	@AuraEnabled
	public static DraftResult mergeArticles(
		String draftTitle,
		String draftBody,
		String existingTitle,
		String existingBody
	) {
		// Implement merge logic here
		ConnectApi.WrappedValue inputValueDraftTitle = new ConnectApi.WrappedValue();
		inputValueDraftTitle.value = draftTitle;

		ConnectApi.WrappedValue inputValueDraftBody = new ConnectApi.WrappedValue();
		inputValueDraftBody.value = draftBody;

		ConnectApi.WrappedValue inputValueExistingTitle = new ConnectApi.WrappedValue();
		inputValueExistingTitle.value = existingTitle;

		ConnectApi.WrappedValue inputValueExistingBody = new ConnectApi.WrappedValue();
		inputValueExistingBody.value = existingBody;

		Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
		inputParams.put('Input:draftTitle', inputValueDraftTitle);
		inputParams.put('Input:draftBody', inputValueDraftBody);
		inputParams.put('Input:existingTitle', inputValueExistingTitle);
		inputParams.put('Input:existingBody', inputValueExistingBody);

		// ====== STEP 3: Call PromptUtils ======
		String responseJson = PromptUtils.invokePrompt(
			'KnowledgeArticleMergeGenerator',
			inputParams
		);
		System.debug('Response JSON from prompt template: ' + responseJson);
		DraftResult draftResult = (DraftResult) JSON.deserialize(
			responseJson,
			DraftResult.class
		);
		draftResult.duplicates = new List<DuplicateArticle>();
		draftResult.isDuplicateFound = false;

		return draftResult;
	}

	@AuraEnabled
	public static void mergeIntoExistingArticle(
		String draftTitle,
		String draftBody,
		Id existingArticleVersionId
	) {
		try {
			Knowledge__kav publishedVersion = [
				SELECT Id, Title, Article_Body__c, KnowledgeArticleId
				FROM Knowledge__kav
				WHERE Id = :existingArticleVersionId
				AND PublishStatus = 'Online'
				Order by CreatedDate DESC
				LIMIT 1
			];
			Id draftArticleVersionId = KbManagement.PublishingService.editOnlineArticle(
				publishedVersion.KnowledgeArticleId,
				false
			);
			System.debug('New Draft Article Version ID: ' + draftArticleVersionId);

			// Step 2: Query the draft version record
			Knowledge__kav draftVersion = [
				SELECT Id, Title, Article_Body__c
				FROM Knowledge__kav
				WHERE Id = :draftArticleVersionId
				LIMIT 1
			];

			// Step 3: Update the draft version with new content
			draftVersion.Title = draftTitle;
			draftVersion.Article_Body__c = draftBody;
			String safeUrlName = draftTitle != null
				? draftTitle.replaceAll('[^a-zA-Z0-9]', '-').toLowerCase()
				: 'article-' + System.currentTimeMillis();

			draftVersion.UrlName = safeUrlName;
			update draftVersion;

			// Step 4: Publish the draft version
			// KbManagement.PublishingService.publishArticle(draftArticleVersionId, true);
			// System.debug('Article republished successfully: ' + draftArticleVersionId);
		} catch (Exception e) {
			System.debug('Exception in mergeIntoExistingArticle: ' + e.getMessage());
		}
	}

	// Wrapper to send draft + duplicates
	public class DraftResult {
		@AuraEnabled
		public String title { get; set; }
		@AuraEnabled
		public String body { get; set; }
		@AuraEnabled
		public Boolean isDuplicateFound { get; set; }
		@AuraEnabled
		public List<DuplicateArticle> duplicates { get; set; }
	}

	// Inner class for duplicate articles
	public class DuplicateArticle {
		@AuraEnabled
		public Id articleId { get; set; }
		@AuraEnabled
		public String title { get; set; }
		@AuraEnabled
		public String body { get; set; }
	}
}