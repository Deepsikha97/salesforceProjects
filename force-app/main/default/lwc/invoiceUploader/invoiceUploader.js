import { LightningElement, api, wire, track } from 'lwc';
import extractTextFromFile from '@salesforce/apex/OcrSpaceService.extractTextFromFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
export default class InvoiceUploader extends LightningElement {
    acceptedFormats = ['.pdf', '.jpg', '.jpeg', '.png'];
    errorMsg = null;
    showErrorMsg = false;
    showOcrText = false; // New property to control OCR text display
    ocrText = null; // New property to hold extracted OCR text
    isModalOpen = false;
    @api recordId;

    /**
     * Public method to open modal from parent components
     */
    @api
    open() {
        this.isModalOpen = true;
    }

    /**
     * Public method to close modal from parent components
     */
    @api
    close() {
        this.isModalOpen = false;
        this.showErrorMsg = false;
        this.errorMsg = null;
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
        this.showErrorMsg = false;
        this.errorMsg = null;
    }

    async handleUploadFinished(event) {
        this.errorMsg = null;
        this.showErrorMsg = false;
        this.showOcrText = false;
        this.ocrText = null;
        this.extractedFields = null;

        const uploadedFiles = event.detail.files;

        // Allow only 1 file
        if (uploadedFiles.length > 1) {
            this.errorMsg = 'Please upload only 1 file.';
            this.showErrorMsg = true;
            return;
        }

        const contentVersionId = uploadedFiles[0].contentVersionId;

        try {
            // Call Apex OCR service
            const result = await extractTextFromFile({ contentVersionId });
            console.log('OCR Result from Apex:', result);

            if (result.isErroredOnProcessing) {
                throw new Error(result.errorMessage || 'OCR failed.');
            }

            // Show raw parsed text
            this.showOcrText = true;
            this.ocrText = result.parsedResults?.[0]?.parsedText || 'No text parsed.';

            // Store structured fields (to display in UI)
            this.extractedFields = {
                invoiceNumber: result.invoiceNumber,
                amount: result.amount,
                customerName: result.customerName,
                productName: result.productName,
                invoiceDate: result.invoiceDate
            };

            console.log('Extracted fields:', this.extractedFields);

        } catch (error) {
            this.showErrorMsg = true;
            this.showOcrText = false;
            this.ocrText = null;
            this.errorMsg = 'Error: ' + (error.body?.message || error.message);
            console.error('OCR Error:', error);
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;

        // Ensure extractedFields exists and update reactively
        this.extractedFields = Object.assign({}, this.extractedFields || {});
        this.extractedFields = { ...this.extractedFields, [field]: value };
    }
    
    handleSave() {
        const fields = {
            Invoice_Number__c: this.extractedFields.invoiceNumber,
            Amount__c: this.extractedFields.amount,
            Customer_Name__c: this.extractedFields.customerName,
            Product_Name__c: this.extractedFields.productName,
            Invoice_Date__c: this.extractedFields.invoiceDate,
        };

        // If linking to a parent (e.g., Account or Case), add it here
        if (this.recordId) {
            fields.Account__c = this.recordId; 
        }

        const recordInput = { apiName: 'Expense__c', fields };

        createRecord(recordInput)
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Invoice created successfully',
                        variant: 'success'
                    })
                );
                this.closeModal();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error creating record',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }
}