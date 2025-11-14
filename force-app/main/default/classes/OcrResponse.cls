// Top-level wrapper for OCR API response
public class OcrResponse {
    @AuraEnabled public List<ParsedResult> parsedResults { get; set; }
    @AuraEnabled public Integer oCRExitCode { get; set; }
    @AuraEnabled public Boolean isErroredOnProcessing { get; set; }
    @AuraEnabled public String errorMessage { get; set; }
    @AuraEnabled public String errorDetails { get; set; }

    // Invoice-specific fields (populated by your parsing logic)
    @AuraEnabled public String invoiceNumber { get; set; }
    @AuraEnabled public String invoiceDate { get; set; }
    @AuraEnabled public String customerName { get; set; }
    @AuraEnabled public String productName { get; set; }
    @AuraEnabled public Decimal amount { get; set; }

    public class ParsedResult {
        @AuraEnabled public String parsedText { get; set; }
        @AuraEnabled public String textOrientation { get; set; }
        @AuraEnabled public Integer fileParseExitCode { get; set; }
    }
}