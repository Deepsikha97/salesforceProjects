public with sharing class QuickVoiceNoteController  {
    @AuraEnabled
    public static void saveVoiceNote(String transcript, Id recordId) {
        if (String.isBlank(transcript) || recordId == null) {
            throw new AuraHandledException('Transcript or Record Id missing.');
        }

        // Create ContentVersion (Enhanced Note backend)
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Voice Note - ' + DateTime.now().format();
        cv.PathOnClient = 'VoiceNote.txt';
        cv.VersionData = Blob.valueOf(transcript);
        insert cv;

        // Get the ContentDocumentId from the inserted ContentVersion
        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        // Link the Note (ContentDocument) to the record
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = insertedCv.ContentDocumentId;
        cdl.LinkedEntityId = recordId;
        cdl.ShareType = 'V';      // Viewer
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }
}