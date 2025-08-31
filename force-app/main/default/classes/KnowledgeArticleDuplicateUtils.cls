public with sharing class KnowledgeArticleDuplicateUtils {
	/**
	 * Step 1: Fetch possible duplicate articles using SOSL
	 */
	public static List<Knowledge__kav> findCandidateDuplicates(
		String title,
		String body,
		Integer limitSize
	) {
		String searchQuery = title;

		List<List<SObject>> searchList = [
			FIND :searchQuery
			IN ALL FIELDS
			RETURNING Knowledge__kav(Id, Title, Article_Body__c LIMIT :limitSize)
		];

		return (List<Knowledge__kav>) searchList[0];
	}

	/**
	 * Step 2: Send candidates + new article content to Einstein GPT
	 * to semantically check for duplicates
	 */
	@AuraEnabled
	public static List<String> checkSemanticDuplicates(
		String newTitle,
		String newBody,
		Integer limitSize
	) {
		List<Knowledge__kav> candidates = findCandidateDuplicates(
			newTitle,
			newBody,
			limitSize
		);

		if (candidates.isEmpty()) {
			return new List<String>();
		}

		// Build GPT prompt
		String articleText = '';
		for (Knowledge__kav art : candidates) {
			articleText +=
				'\n\n[Article Id: ' +
				art.Id +
				' | Title: ' +
				art.Title +
				' | Body: ' +
				art.Article_Body__c +
				']';
		}
		system.debug('Built GPT prompt: ' + articleText);
		// Convert GPT response into list<String>
		ConnectApi.WrappedValue inputValueMapArticleTitle = new ConnectApi.WrappedValue();
		inputValueMapArticleTitle.value = newTitle;

		ConnectApi.WrappedValue inputValueArticleMapBody = new ConnectApi.WrappedValue();
		inputValueArticleMapBody.value = newBody;

		ConnectApi.WrappedValue inputValueMatchedArticle = new ConnectApi.WrappedValue();
		inputValueMatchedArticle.value = articleText;

		Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
		inputParams.put('Input:articleTitle', inputValueMapArticleTitle);
		inputParams.put('Input:articleBody', inputValueArticleMapBody);
		inputParams.put('Input:matchedArticle', inputValueMatchedArticle);

		// ====== STEP 3: Call PromptUtils ======
		String responseJson = PromptUtils.invokePrompt(
			'KnowledgeArticleDuplicateGenerator',
			inputParams
		);
		// Convert GPT response into list<String>
		Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(
			responseJson
		);
		String bestMatchId = (String) result.get('Id');
		Integer similarityScore = (Integer) result.get('SimilarityScore');
		String reason = (String) result.get('Reason');

		System.debug('Best Match Article Id: ' + bestMatchId);
		System.debug('Score: ' + similarityScore);
		System.debug('Reason: ' + reason);

		if (bestMatchId != null && similarityScore >= 70) {
			return new List<String>{ bestMatchId };
		} else {
			return new List<String>();
		}
	}
}