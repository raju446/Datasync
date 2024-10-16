public class DownstreamSyncScheduler implements Schedulable {
    private String query;
    private String objectName;
    private String toEmails;
    
    public DownstreamSyncScheduler(String query, String objectName, String toEmails) {
        this.query = query;
        this.objectName = objectName;
        this.toEmails = toEmails;
    }
    
    public void execute(SchedulableContext sc) {
        try {
            if (String.isNotBlank(query) && String.isNotBlank(objectName)) {
                UpsertBatchProcessor batch = new UpsertBatchProcessor(query, objectName, toEmails, '', '', '');
                Database.executeBatch(batch);
            } else {
                System.debug('Invalid parameters for DownstreamSyncScheduler: query=' + query + ', objectName=' + objectName +  ', toEmails=' + toEmails);
            }
        } catch (Exception e) {
            System.debug('Error in DownstreamSyncScheduler: ' + e.getMessage());
            // Consider implementing a more robust error handling mechanism here,
            // such as sending an email notification or creating an error log record
        }
    }
    
    public static String scheduleJob(String query, String objectName, String toEmails, String jobName, String cronExpression) {
        DownstreamSyncScheduler scheduler = new DownstreamSyncScheduler(query, objectName, toEmails);
        return System.schedule(jobName, cronExpression, scheduler);
    }
}

// Sample code to invoke the scheduler
/*public class DownstreamSyncExample {
    public static void scheduleDownstreamSync() {
        // Example: Schedule a job to sync Account records every day at 2 AM
        String accountQuery = 'SELECT Id, Name, MyExtId__c FROM Account WHERE MyExtId__c != null';
        String objectName = 'Account';
        String externalIdField = 'MyExtId__c';
        String toEmails = 'admin@example.com';
        String jobName = 'Daily Account Sync';
        String cronExp = '0 0 2 * * ?'; // Run every day at 2 AM
        
        String jobId = DownstreamSyncScheduler.scheduleJob(accountQuery, objectName, externalIdField, toEmails, jobName, cronExp);
        System.debug('Scheduled job ID: ' + jobId);
        
        // Example: Schedule a job to sync Contact records every Monday at 3 AM
        String contactQuery = 'SELECT Id, FirstName, LastName, Email, MyExtId__c FROM Contact WHERE MyExtId__c != null';
        objectName = 'Contact';
        externalIdField = 'MyExtId__c';
        jobName = 'Weekly Contact Sync';
        cronExp = '0 0 3 ? * MON'; // Run every Monday at 3 AM
        
        jobId = DownstreamSyncScheduler.scheduleJob(contactQuery, objectName, externalIdField, toEmails, jobName, cronExp);
        System.debug('Scheduled job ID: ' + jobId);
    }
}*/