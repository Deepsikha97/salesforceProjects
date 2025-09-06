public with sharing class FileController {

    // Wrapper class for LWC
    public class FileWrapper {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Title { get; set; }
        @AuraEnabled public String FileExtension { get; set; }
        @AuraEnabled public Id VersionId { get; set; }
        @AuraEnabled public Id ContentDocumentId { get; set; } // Explicit field for preview
        @AuraEnabled public String ThumbnailUrl { get; set; } // Thumbnail for PDFs
    }

    // Fetch files related to a record
    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getFiles(Id recordId) {
        // Query ContentDocumentLink -> ContentDocument (LatestPublishedVersionId)
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Id,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            ORDER BY ContentDocument.CreatedDate DESC
        ];

        List<FileWrapper> results = new List<FileWrapper>();

        for (ContentDocumentLink cdl : links) {
            FileWrapper fw = new FileWrapper();
            fw.Id = cdl.ContentDocument.Id;
            fw.ContentDocumentId = cdl.ContentDocument.Id;
            fw.Title = cdl.ContentDocument.Title;
            fw.FileExtension = cdl.ContentDocument.FileExtension;
            fw.VersionId = cdl.ContentDocument.LatestPublishedVersionId;

            // Generate thumbnail URL for PDFs
            if (fw.FileExtension != null && fw.FileExtension.toLowerCase() == 'pdf') {
                fw.ThumbnailUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + fw.VersionId;
            }

            results.add(fw);
        }

        return results;
    }
}