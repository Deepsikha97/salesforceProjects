public  class ChatPublisher {
    @AuraEnabled
    public static void sendMessage(String sender, String message){
        try {
            Chat_Message__e chatMe = new Chat_Message__e();
            chatMe.Sender__c = sender;
            chatMe.Message__c = message;
            chatMe.TimeStamp__c = System.now();

            EventBus.publish(chatMe);
            System.debug('Message sent: ' + chatMe);
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}