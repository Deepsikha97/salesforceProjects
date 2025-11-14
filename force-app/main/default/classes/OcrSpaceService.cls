public with sharing class OcrSpaceService {
    private static final Long ONE_MIB = 1024L * 1024L; // 1 MB

    @AuraEnabled
    public static OcrResponse extractTextFromFile(Id contentVersionId) {
        ContentVersion cv = [
            SELECT Id, Title, FileExtension, VersionData, ContentSize
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        if (cv.ContentSize > ONE_MIB) {
            return buildErrorResponse(
                'File size exceeds 1 MB limit.',
                'Please upload a file smaller than 1 MB.'
            );
        }

        try {
            // API key (ideally store in Named Credential or Custom Metadata)
            String apiKey = 'ghsdgahgashga';// Replace with your actual API key

            // Convert file to Base64
            String mimeType = getMimeType(cv.FileExtension);
            String base64Content = EncodingUtil.base64Encode(cv.VersionData);
            String base64Param = 'data:' + mimeType + ';base64,' + base64Content;

            // OCR.Space expects x-www-form-urlencoded with base64Image
            String body = 'base64Image=' + EncodingUtil.urlEncode(base64Param, 'UTF-8');

            // Prepare HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:OCR_Space/parse/image'); // Named Credential
            req.setMethod('POST');
            req.setHeader('apikey', apiKey);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(body);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                System.debug('OCR Response (raw): ' + res.getBody());
                // Pass JSON to processOcrResult for enrichment
                return processOcrResult(res.getBody());
            } else {
                return buildErrorResponse(
                    'OCR API call failed',
                    'Status: ' + res.getStatusCode() + ', Body: ' + res.getBody()
                );
            }
        } catch (Exception e) {
            return buildErrorResponse('Exception during OCR callout', e.getMessage());
        }
    }

    private static OcrResponse processOcrResult(String jsonResponse) {
        OcrResponse resp = (OcrResponse) JSON.deserialize(jsonResponse, OcrResponse.class);

        if (resp.parsedResults == null || resp.parsedResults.isEmpty()) {
            resp.isErroredOnProcessing = true;
            resp.errorMessage = 'No parsed results returned from OCR API';
            return resp;
        }

        // Join all pages' parsed text
        String parsedText = '';
        for (OcrResponse.ParsedResult pr : resp.parsedResults) {
            parsedText += pr.parsedText + '\n';
        }

        // Keep both original and normalized
        String originalText = parsedText;
        String normalizedText = parsedText != null ? parsedText.toUpperCase() : '';
        System.debug('Original Parsed Text: ' + originalText);
        System.debug('Normalized Parsed Text: ' + normalizedText);
        ConnectApi.WrappedValue inputValueParsedText = new ConnectApi.WrappedValue();
        inputValueParsedText.value = normalizedText;
        Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
        inputParams.put('Input:parseText', inputValueParsedText);

        // ====== STEP 3: Call PromptUtils ======
		String responseJson = PromptUtils.invokePrompt(
			'tr11',
			inputParams
		);
        responseJson = responseJson.trim();
        responseJson = responseJson.replaceAll('[\\n\\r]', '').replaceAll('\\s{2,}', ' ');
        System.debug('Response JSON from prompt template: ' + responseJson);
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseJson); 
        
        resp.isErroredOnProcessing = false;
        resp.invoiceNumber = (String) responseMap.get('invoiceNumber')  != null ? (String) responseMap.get('invoiceNumber') : '';
        resp.invoiceDate = (String) responseMap.get('invoiceDate') != null ? (String) responseMap.get('invoiceDate') : '';  
        resp.amount = responseMap.get('amount') != null ? Decimal.valueOf(String.valueOf(responseMap.get('amount'))) : 0;
        resp.customerName = (String) responseMap.get('customerName') != null ? (String) responseMap.get('customerName') : '';
        resp.productName = (String) responseMap.get('productName') != null ? (String) responseMap.get('productName') : '';
        resp.errorMessage = '';
        resp.errorDetails = '';
        resp.oCRExitCode = 0; 
        return resp;
    }




    private static OcrResponse buildErrorResponse(String msg, String details) {
        OcrResponse errorResponse = new OcrResponse();
        errorResponse.isErroredOnProcessing = true;
        errorResponse.errorMessage = msg;
        errorResponse.errorDetails = details;
        errorResponse.oCRExitCode = -1;
        errorResponse.parsedResults = new List<OcrResponse.ParsedResult>();
        return errorResponse;
    }

    private static String getMimeType(String ext) {
        ext = ext != null ? ext.toLowerCase() : '';
        if (ext == 'png') return 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
        if (ext == 'pdf') return 'application/pdf';
        return 'application/octet-stream'; // fallback
    }
}