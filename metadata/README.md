# Metadata

Each .yaml file lists available resources along with their metadata.



### datasets

datasets.yaml follows this structure - for explanations see the text in bold.

-
    name: 'Infant directed speech preference' **How do you want to call your meta-analysis, e.g. in the datasets overview** 
    
    domain: early_language **Currently the domains _early\_language_ and _cognitive\_development_ are available**  
    
    short_name: idspref **For internal reference to the dataset, also used in the (upcoming) metalabR package**
    
    key: 1HvD_DvcKqzlBuiirVdDVr9t2DnWtKmiv98ee8vp345w **Copy this key from the google sheet** 
    
    filename: infant_directed_speech_preference **How do you want the downloadable .csv to be called?**
    
    citation: 'Dunst, Gorman, & Hamby (2012)' **This should be following APA conventions, et al. is fine for long author lists**
    
    internal_citation: '(Dunst, Gorman, & Hamby, 2012)' **Same as the previous one, just with parentheses**
    
    link: 'http://earlyliteracylearning.org/cellreviews/cellreviews_v5_n1.pdf'  **Is there a link to a website, supplementary materials, or similar?**
    
    full_citation: 'Dunst, C. J., Gorman, E., & Hamby, D. W. (2012). Preference for infant-directed speech in preverbal young children. Center for Early Literacy Learning, 5(1).' **Full APA citation, both for peer reviewed works and so-called grey literature**
    
    doi: "" **If possible, add a DOI, e.g. from PsyArXiv or MetaArXiv**
    
    systematic: yes **Was a systematic search conducted? This distinguishes seed meta-analyses from those with complete systematic searches, i.e. classic meta-analyses**
    
    search_strategy: '"Studies were located using [..]"' **This can be a full quote from the paper**
    
    reliability: "" **Did two or mode coders run reliability checks?**
    
    source: 'adapted from published MA' **What is the source?**
    
    last_update: '2012-01-01' **When did we last update the content?**
    
    link_fields: 'http://earlyliteracylearning.org/cellreviews/cellreviews_v5_n1.pdf' **Where can readers find explanations of the coded moderators, especially those added to the mandatory MetaLab fields**
    
    short_desc: 'Looking times as a function of whether infant-directed vs. adult-directed speech is presented as stimulation.' **What is the main research question?**
    
    description: 'Looking times as a function of whether infant-directed vs. adult-directed speech is presented as stimulation, in infants aged 0 - 12 months.' **As before, but with age added**
    
    curator: 'Alex Cristia' **Who to contact in case you want to update the dataset or have questions**
    
    src: media/datasets/ids.png **Add a picture that nicely summarizes the MA**
    
    longitudinal: no ** Were effect sizes sampled from the same participants over a longer period of time?**
    
    moderators: [speaker, speech_type] **Which additional moderator columns should we display in the visualizations? These have to be the column names**
    
    subset: [] **Is there a column allowing for subsetting, e.g. on age or stimulus type? Note that these subsetting columns need to contain only TRUE and FALSE**
    
    comment: '' **Anything else you would like to mention**
