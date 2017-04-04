classdef ParadigmSIFT < ParadigmDataflowSimplified
    % Source Information Toolbox adapter paradigm.
    %
    % This paradigm exposes SIFT-derived connectivity features within BCILAB.
    %
    % Name:
    %   Source Information Flow Toolbox Adapter
    %
    
    
    methods
      
        function defaults = preprocessing_defaults(self)
            % define the default pre-processing parameters of this paradigm
            defaults = { ...
                'FilterOrdering', {'flt_clean_settings','flt_ica','flt_selchans','flt_reref'} ...
                'Resampling', { ...
                    'SamplingRate', 128} ...
                'DataCleaning', { ...
                    'DataSetting', {'1.1-beta' ...
                        'ChannelDropoutRepair', 'off'}} ...
                'ICA', { ...
                    'Variant', 'robust_sphere' ...
                    'DataCleaning', { ...
                        'DataSetting', 'off'} ...
                    'TransformData', true} ...
                'ChannelSelection', { ...
                    'Channels', {'FP1','FP2','Fz','FCz','C3','Cz','C4','PO3','POz','PO4','O1','O2'} ...
                    'FindClosest', true} ...
                'Rereferencing', 'on' ...
                'FIRFilter', { ...
                    'Frequencies', [45 50] ...
                    'Mode', 'lowpass'} ...
                'EpochExtraction', { ...
                    'TimeWindow', [-0.5 1.5]}};
        end
        
        function defaults = machine_learning_defaults(self)
            defaults = {'proximal' ...
                'Regularizers', { ...
                    'Term1', 'l1' ...
                    'Term2', 'l2' ...
                    'Term4', {'l2' ...
                        'LinearOperator', '@(x)[vec(diff(x,[],3));vec(diff(x,[],4))]' ...
                        'NonorthogonalTransform', true} ...
                    'Term5', {'trace' ...
                        'LinearOperator', '@(x)reshape(permute(x,[1 2 4 3 5]),a*b*d,c,[])'} ...
                    'Term6', {'trace' ...
                        'LinearOperator', '@(x)reshape(x,a*b*c,d,[])'}} ...
                'TermWeights', {[1 1 1 1 1]} ...
                'SolverOptions', { ...
                    'MaxIterations', 150 ...
                    'AbsoluteTolerance', 5e-06 ...
                    'CouplingParameter', 8} ...
                'LambdaSearch', { ...
                    'Lambdas', [8 5.06302637588112 3.20427951035849 2.02791895958006 1.2834258975629 0.812252396356235 0.514056913328033 0.325335463860483 0.205897754316893 0.13030822010514 0.0824692444233059 0.0521929949642731 0.0330318137675431 0.020905118043533 0.0132303955056645 0.00837323017606479 0.00529923565409247] ...
                    'FoldMargin', 5 ...
                    'ParameterMetric', 'auc' ...
                    'ReturnRegpath', false} ...
                'Verbosity', 1};
        end
        
        function defaults = machine_learning_search_defaults(self)
            defaults = {'logreg' ...
                'Lambda',0.001, ...
                'Variant', {'l2' 'LambdaSearch',false}};
        end
        
        function model = feature_adapt(self,varargin)
            % configure and adapt parameters for SIFT's online pipeline
            g = arg_define(varargin, ...
                    arg_norep('signal'), ...
                    arg_sub({'connPipeline','ConnectivityPipeline'}, ...
                        {...
                        'EEG',struct('srcpot',1,'icaweights',1), ...
                        'Channels', {} ...
                        'Preprocessing', { ...
                            'SignalType', {'Channels' ...
                                'ConvertChanlocs2Dipfit', 'off'} ...
                            'NormalizeData', { ...
                                'Method', {'time'}}} ...
                        'Modeling', {'Segmentation VAR' ...
                            'Algorithm', {'Group Lasso (ADMM)' ...
                                'WarmStart', 'on' ...
                                'NormCols', 'norm' ...
                                'ADMM_Options', { ...
                                    'ReguParamLambda', 0.2 ...
                                    'AugLagrangParamRho', 2 ...
                                    'MaxIterations', 300 ...
                                    'LambdaUpdateThreshold', 0.001 ...
                                    'LambdaUpdateCount', 5 ...
                                    'RelativeTolerance', 0.001}} ...
                            'WindowLength', 0.66 ...
                            'WindowStepSize', 0.05 ...
                            'Detrend', { ...
                                'DetrendingMethod', 'linear'} ...
                            'VerbosityLevel', 0} ...
                        'AutoSelectModelOrder', 'off' ...
                        'Connectivity', { ...
                            'ConnectivityMeasures', {'dDTF08'} ...
                            'Frequencies', [1:15] ...
                            'VerbosityLevel', 0} ...
                        'Validation', 'off' ...
                        'PrintValidation', true}, @onl_siftpipeline,'Connectivity extraction options.'), ...
                    arg_subtoggle({'lambdaSelection','RegularizationParameterSelection'},[], { ...
                        arg_sub({'validationMetric','ValidationMetric'},{},@est_validateMVAR,'Model validation options. Used for selection optimal lambda (VAR regularization).'), ...
                        arg({'lambdaGrid','LambdaGrid'},logspace(log10(1e-5),log10(100),10),[],'Lambda grid. This is a row vector of possible lambda values to search over','shape','row') ...
                    },'Options for selecting optimal lambda. This only applies if you are using regularized model fitting methods that accept a "lambda" parameter'), ...
                    arg({'valueFormat','ValueFormat'},'log-magnitude',{'complex','components','mixed','magnitude','sqrt-magnitude','log-magnitude','phase','polar'},'Output value format. Formatting for partially complex-valued features. Mixed means as-is, components means to separate real and imaginary components (both as real), magnitude retains only the complex magnitude, phase retains only the phase, and polar retains both magnitude and phase as real numbers.'), ...
                    arg({'featureShape','FeatureShape'},'[CxCxFxTxM] (5d tensor)',{'[CCFTMx1] (unstructured vector)','[CxCxFxTxM] (5d tensor)','[CCMxFT] (time/freq row sparsity matrix)','[CCxFTM] (per-link column sparsity matrix)','[CCxFT]_m1,..,[CCxFT]_mk (low-rank space/time structure, sparse methods)','[FxT]_c11,..,[FxT]_cnn (low-rank time/freq structure, sparse links)','[CxC]_ft1,..,[CxC]_ft2 (low-rank link structure, sparse time/freq)'},'Feature tensor arrangement. Features can be arranged in tensor or matrix or block-diagonal matrix form - most useful with the DAL classifier.'), ...
                    arg({'vectorizeFeatures','VectorizeFeatures'},true,[],'Vectorize feature tensors. This is for classifiers that cannot handle matrix or tensor-shaped features.'), ...
                    arg({'cacheFeatures','CacheFeatures'},'disk',{'no','memory','disk'},'Whether/how to cache features. This generally applies only to offline processing. If set to memory, features will be cached in-memory. If set to disk, features will be cached on disk and reused across MATLAB sessions/instances. Note that the latter will produce huge amounts of data.'), ...
                    arg({'logBias','LogBias'},1e-4,[],'Bias for logarithms. This is to shift connectivity values to a Gaussian distribution and also to prevent negative infinities from occurring.'), ...
                    arg({'verb','Verbosity','verbosity'},true,[],'Verbose output'));
 
            % make sure to clear persistent state of the SIFT estimator so we carry nothing over 
            % between folds
            clear mvar_glADMM;
                
            if g.lambdaSelection.arg_selection ...
                    && g.lambdaSelection.validationMetric.checkWhiteness.arg_selection ...
                    && length(g.lambdaSelection.validationMetric.checkWhiteness.whitenessCriteria)>1
                error('BCILAB:ParadigmSIFT:MoreThanOneIC','Only one WhitenessCriteria can be selected for ParadigmSIFT.'); end
            
            if g.lambdaSelection.arg_selection ...
                 && sum([g.lambdaSelection.validationMetric.checkConsistency.arg_selection ...
                    g.lambdaSelection.validationMetric.checkResidualVariance.arg_selection ...
                    g.lambdaSelection.validationMetric.checkStability.arg_selection ...
                    g.lambdaSelection.validationMetric.checkWhiteness.arg_selection]) > 1
                error('BCILAB:ParadigmSIFT:MoreThanOneValidationMetric','Only one validation metric (Whiteness,Stability,ResidualVariance, or Consistency) may be selected for ParadigmSIFT'); end
                
            % force window length and step size to match epoch length
            model.siftPipelineConfig = g.connPipeline;
            
            continuous = self.make_continuous(g.signal);
            
            % lambda selection. 
            % Here we use one of validation metrics to select lambda
            if g.lambdaSelection.arg_selection
                if g.verb
                    fprintf('Performing grid search for optimal lambda\n'); end
                
                % fit model and perform validation
                connPipelineRange = g.connPipeline;
                if strcmpi(g.connPipeline.modeling.algorithm.arg_selection,'Group Lasso (ADMM)')
                    connPipelineRange.modeling.algorithm.admm_args.lambda = search(g.lambdaSelection.lambdaGrid);
                else
                    error('Unknown modeling method %s. Disable lambda search and try again',g.connPipeline.modeling.algorithm.arg_selection);
                    % FIXME: ADD ADDITIONAL CASES FOR OTHER ALGORITHMS...s
                end
                
                [min_idx,all_inputs,all_outputs] = utl_gridsearch('clauses',@onl_siftpipeline,connPipelineRange,'EEG',continuous,'connectivity',[],'validation',g.lambdaSelection.validationMetric); %#ok<ASGLU>
                
                % pick optimal lambda
                if g.lambdaSelection.validationMetric.checkConsistency.arg_selection
                    % objective function (minimize) is mean percent
                    % consistency over epochs
                    objFun = cellfun(@(x) x{1}.CAT.validation.PCstats.PC,all_outputs,'UniformOutput',false);
                    objFun = cellfun(@mean,objFun);
                elseif g.lambdaSelection.validationMetric.checkResidualVariance.arg_selection
                    % objective function (minimize) is residual whiteness
                    % over epochs
                    objFun = cellfun(@(x) x{1}.CAT.validation.residualstats.variance,all_outputs,'UniformOutput',false);
                    objFun = cellfun(@(x) mean(cell2mat(x)),objFun);
                elseif g.lambdaSelection.validationMetric.checkStability.arg_selection
                    % objective function (minimize) is fraction of epochs
                    % with unstable VAR model
                    objFun = cellfun(@(x) x{1}.CAT.validation.stabilitystats.stability,all_outputs,'UniformOutput',false);
                    objFun = 1-cellfun(@(x) nnz(x)/numel(x),objFun);
                elseif g.lambdaSelection.validationMetric.checkWhiteness.arg_selection
                    whitenessCriterion = lower(hlp_variableize(g.lambdaSelection.validationMetric.checkWhiteness.whitenessCriteria{1}));
                    % objective function (minimize) is 1-pvalue where
                    % a sufficiently large pvalue indicates white residuals
                    objFun = cellfun(@(x) x{1}.CAT.validation.whitestats.(whitenessCriterion).pval,all_outputs,'UniformOutput',false);
                    objFun = 1-cellfun(@mean,objFun);
                end
                
                % get the min of the objective function and select lambda
                [min_val min_idx] = min(objFun); %#ok<NCOMMA>
                optLambda = g.lambdaSelection.lambdaGrid(min_idx);
                if g.verb
                  fprintf('Optimal lambda found. lambda=%05g; objFun(lambda)=%0.5g\n',optLambda,min_val); end
                
                % retrieve the configuration structure corresponding to the
                % optimal lambda
                model.siftPipelineConfig.modeling = all_outputs{min_idx}{2}.modeling;
                if strcmpi(g.connPipeline.modeling.algorithm.arg_selection,'Group Lasso (ADMM)')
                    model.siftPipelineConfig.modeling.algorithm.admm_args.lambda = optLambda;
                end
            end
            model.valueFormat = g.valueFormat;
            model.featureShape = g.featureShape;
            model.vectorizeFeatures = g.vectorizeFeatures;
            model.cacheFeatures = g.cacheFeatures;
            model.logBias = g.logBias;
            model.args = g;
            
            % run feature extraction for a short signal to get shape information
            tmpsignal = exp_eval(set_selepos(g.signal,1:min(3,g.signal.trials)));
            if ~strcmp(g.featureShape,'[CCFTMx1] (unstructured vector)')                
                [dummy,model.shape] = self.feature_extract(tmpsignal,model); end %#ok<ASGLU>
        end
        
        function [features,shape] = feature_extract(self,signal,featuremodel)            
            if ~isfield(featuremodel,'cacheFeatures')
                featuremodel.cacheFeatures = 'memory'; end
            
            % pre-calculate the placement indices within each epoch
            winStartIdx = 1 : round(featuremodel.siftPipelineConfig.modeling.winstep*signal.srate) : signal.pnts - ceil(featuremodel.siftPipelineConfig.modeling.winlen * signal.srate);
            % calculate placement indices across all epochs (after make_continuous)
            winStartIdx = 1 + bsxfun(@plus,winStartIdx'-1, (0:signal.trials-1)*signal.pnts);
            featuremodel.siftPipelineConfig.modeling.winStartIdx = winStartIdx(:);
            
            % extract connectivity features per epoch
            call = {@onl_siftpipeline,featuremodel.siftPipelineConfig,'EEG',self.make_continuous(signal),'arg_direct',true};
            if onl_isonline || strcmp(featuremodel.cacheFeatures,'no')
                EEG = call{1}(call{2:end});
            elseif strcmp(featuremodel.cacheFeatures,'memory')
                hlp_microcache('conn','max_key_size',2^30,'max_result_size',2^30);
                EEG = hlp_microcache('conn',call{:});
            elseif strcmp(featuremodel.cacheFeatures,'disk')
                EEG = hlp_diskcache('features',call{:});
            else
                error('Unsupported CacheFeatures setting: %s',hlp_tostring(featuremodel.cacheFeatures,100));
            end
            
            rawfeatures = cellfun(@(connmethod) EEG.CAT.Conn.(connmethod), ...
                featuremodel.siftPipelineConfig.connectivity.connmethods, ...
                'UniformOutput',false);
            
            % reshape them to separate time points from trials {CxCxFxTxN, CxCxFxTxN, ...}
            for m=1:length(rawfeatures)
                [C,C2,F,TN] = size(rawfeatures{m});
                rawfeatures{m} = reshape(rawfeatures{m},C,C2,F,[],signal.trials);
            end
            
            % combine into single tensor: CxCxFxTxMxN
            features = permute(cat(6,rawfeatures{:}),[1,2,3,4,6,5]);
            [C,C2,F,T,M,N] = size(features);
            if C2 ~= C || N ~= signal.trials
                error('Unexpected feature shape.'); end
            
            % reshape into desired form (note: all arrays are implicitly xN)
            same_size = @(shape,features) isequal(shape(1:ndims(features)),size(features));
            switch featuremodel.featureShape                
                case '[CxCxFxTxM] (5d tensor)'
                    shape = [C,C,F,T,M];
                    if ~same_size([shape N],features)
                        error('Unexpected feature shape.'); end
                case '[CCMxFT] (time/freq row sparsity matrix)'
                    features = reshape(permute(features,[1 2 5 3 4 6]),[C*C*M,F*T,N]);
                    shape = [C*C*M,F*T];
                    if ~same_size([shape N],features)
                        error('Unexpected feature shape.'); end
                case '[CCxFTM] (per-link column sparsity matrix)'
                    features = reshape(permute(features,[1 2 3 4 5 6]),[C*C,F*T*M,N]);
                    shape = [C*C,F*T*M];
                    if ~same_size([shape N],features)
                        error('Unexpected feature shape.'); end
                case '[CCxFT]_m1,..,[CCxFT]_mk (low-rank space/time structure, sparse methods)'
                    features = reshape(permute(features,[1 2 3 4 5 6]),[C*C,F*T*M,N]);
                    shape = repmat([C*C,F*T],M,1);
                case '[FxT]_c11,..,[FxT]_cnn (low-rank time/freq structure, sparse links)'
                    features = reshape(permute(features,[3 4 1 2 5 6]),[F*T,C*C*M,N]);
                    shape = repmat([F,T],C*C*M,1);
                case '[CxC]_ft1,..,[CxC]_ft2 (low-rank link structure, sparse time/freq)'
                    features = reshape(permute(features,[1 2 3 4 5 6]),[C*C,F*T*M,N]);
                    shape = repmat([C,C],F*T*M,1);
                case '[CCFTMx1] (unstructured vector)'
                    shape = [C*C*F*T*M,1];
                otherwise
                    error('Unrecognized FeatureShape selected.');
            end
            
            % apply value formatting
            switch featuremodel.valueFormat
                case 'complex'
                    features = complex(features);
                case 'mixed'
                    % nothing to do
                case 'magnitude'
                    features = abs(features);
                case 'sqrt-magnitude'
                    features = sqrt(abs(features));
                case 'log-magnitude'
                    features = log(featuremodel.logBias+abs(features));
                case 'phase'
                    features = angle(features);
                    % these two cases will double the first shape parameter for each block
                case 'components'
                    % components are expanded along the first dimension
                    features = permute(cat(ndims(features)+1,real(features),imag(features)),[ndims(features)+1,1:ndims(features)]);
                    shape(:,1) = shape(:,1)*2;
                case 'polar'
                    % components are expanded along the first dimension
                    features = permute(cat(ndims(features)+1,abs(features),angle(features)),[ndims(features)+1,1:ndims(features)]);
                    shape(:,1) = shape(:,1)*2;
                otherwise
                    error(['Unsupported value format: ' featuremodel.valueFormat]);
            end
            
            % do final vectorization if desired
            if featuremodel.vectorizeFeatures
                features = reshape(features,[],signal.trials)'; end
        end
        
        function [featuremodel,conditioningmodel,predictivemodel] = calibrate_prediction_function(self,varargin)
            % Perform calibration of the prediction function; this includes everything except for signal
            % processing. This function can optionally be overridden if some custom feature-extraction /
            % machine learning data flow is desired; its user parameters may be arbitrarily redefined then.
            %
            % This function invokes the feature adaptation, feature extraction and machine learning
            % during the calibration phase (i.e. everything that is required to determine the
            % parameters of the BCI paradigm's prediction function).
            %
            % This function is what gives rise to the "Prediction" top-level argument of the paradigm;
            % as you see below, it has two sub-arguments: FeatureExtraction and MachineLearning, which
            % themselves are defined by feature_adapt() and ml_train().
            %
            % In:
            %   Signal : a signal as pre-processed according to the paradigm's pre-processing pipeline
            %
            %   FeatureExtraction : User parameters for the feature-extraction stage. These parameters
            %                       control how features are extracted from the filtered data before
            %                       they are passed int othe machine learning stage.
            %
            %   Conditioning : User parameters for an optional feature-conditioning stage. These parameters
            %                  control how features are remapped to features that are subsequently received
            %                  by the machine learning.
            %
            %   MachineLearning : Machine learning stage of the paradigm. Operates on the feature
            %                     vectors that are produced by the feature-extraction stage.
            %
            % Out:
            %   FeatureModel : a feature-extraction model as understood by apply_prediction_function()
            %                  or (if not otherwise customized) by the feature_extract() function
            %                  * special feature: if this contains a non-empty field named shape, this
            %                                     value will be passed on to the machine learning method
            %
            %   ConditioningModel : a model that is sandwiched between feature extraction and machine learning,
            %                       generated by feature_adapt_conditioning and understood by feature_apply_conditioning
            %
            %   PredictiveModel : a predictive model, as understood by apply_prediction_function() or
            %                     (if not otherwise customized) by the ml_predict() function
            %
            %
            % Notes:
            %   You may override this function if your prediction function blends traditional
            %   feature extraction and machine learning or otherwise makes this separation
            %   impractical (for example if you have an unusual mapping between training instances
            %   for machine learning and target values in the data set). This function should
            %   declare its arguments using arg_define().
            
            args = arg_define(varargin, ...
                arg_norep({'signal','Signal'}), ...
                arg_sub({'fex','FeatureExtraction'},{},@self.feature_adapt,'Parameters for the feature-adaptation function. These parameters control how features are statistically adapted and extracted from the filtered data before they are passed into the machine learning stage.'), ...
                arg_sub({'cond','Conditioning'},{},@self.feature_adapt_conditioning,'Feature conditioning parameters. Allows to further process features for better usability with classifiers.'), ...
                arg_sub({'ml','MachineLearning'},{'Learner',self.machine_learning_defaults()},@ml_train,'Machine learning stage of the paradigm. Operates on the feature vectors that are produced by the feature-extraction stage.'), ...
                arg_sub({'ml_search','MachineLearningForSearch'},{'Learner',self.machine_learning_search_defaults()},@ml_train,'Machine learning stage for parameter search. This paradigm uses a fast classifier to optimize preproc pipeline parameters, and then uses the slower classifier with the optimized pipeline.'));
            
            % adapt features if necessary
            featuremodel = self.feature_adapt('signal',args.signal, args.fex);
            if isfield(featuremodel,'shape') && ~isempty(featuremodel.shape)
                % check if the learner supports a shape parameter...
                if isfield(args.ml.learner,'shape')
                    args.ml.learner.shape = featuremodel.shape; 
                else
                    warn_once('ParadigmDataflowSimplified:ignoring_shape','The learning function does not appear to support a shape parameter, but the paradigm prefers to supply one; ignoring the shape. This warning will not be shown again during this session.');
                end
            end
            if isfield(featuremodel,'modality_ranges') && ~isempty(featuremodel.modality_ranges)
                % check if the learner supports a modality_ranges parameter...
                if isfield(args.ml.learner,'modality_ranges')
                    args.ml.learner.modality_ranges = featuremodel.modality_ranges; 
                else
                    warn_once('ParadigmDataflowSimplified:ignoring_modality_ranges','The learning function does not appear to support a modality_ranges parameter, but the paradigm prefers to supply one; ignoring the modality_ranges. This warning will not be shown again during this session.');
                end
            end
            
            % try to extract some signal-related properties
            featuremodel.signalinfo.chanlocs = args.signal.chanlocs;
            featuremodel.signalinfo.chaninfo = args.signal.chaninfo;
            
            % extract features
            features = self.feature_extract(args.signal, featuremodel);
            
            % extract target labels
            targets = set_gettarget(args.signal);
            
            % adapt and apply feature conditioning
            conditioningmodel = self.feature_adapt_conditioning('features',features,'targets',targets,args.cond);
            [features,targets] = self.feature_apply_conditioning(features,targets,conditioningmodel);
            
            % run the machine learning stage
            if hlp_iscaller('utl_gridsearch')
                % within a grid search we use the fast and simple ml_search classifier
                predictivemodel = ml_train('data',{features,targets}, args.ml_search);
            else
                % outside the search we use the better ml classifier
                predictivemodel = ml_train('data',{features,targets}, args.ml);
            end            
        end
        
        function visualize_model(self,varargin) %#ok<*INUSD>
            args = arg_define([0 3],varargin, ...
                arg_norep({'parent','Parent'},[],[],'Parent figure.'), ...
                arg_norep({'featuremodel','FeatureModel'},[],[],'Feature model. This is the part of the model that describes the feature extraction.'), ...
                arg_norep({'predictivemodel','PredictiveModel'},[],[],'Predictive model. This is the part of the model that describes the predictive mapping.'), ...
                arg({'signed','SignedWeights'},true,[],'Plot signed weights. Whether the original signed weights should be plotted or their absolute values.'), ...
                arg({'reordering','Reordering'},[],uint32([1 10000]),'Component reordering. Allows to reorder components for plotting.','shape','row','guru',true), ...
                arg({'smoothing_kernel','SmoothingKernel'},[],[],'Smoothing filter kernel. Allows to smooth time/frequency activation.','shape','row','guru',true));
            [featuremodel,predictivemodel] = deal(args.featuremodel,args.predictivemodel);
            fs = featuremodel.shape;
            % get weights and featureshape
            w = predictivemodel.model.w; 
            if numel(w) == prod(fs)+1
                w = w(1:end-1); end
            % reshape into tensor            
            M = ((reshape(w,fs))); 
            % reverse frequency axis for plotting
            M = M(:,:,end:-1:1,:); 
            if ~isempty(args.smoothing_kernel)
                M = filter(args.smoothing_kernel/norm(args.smoothing_kernel),1,M,[],3);
                M = filter(args.smoothing_kernel/norm(args.smoothing_kernel),1,M,[],4);
            end
            if ~isempty(args.reordering)
                M = M(args.reordering,args.reordering,:,:); end
            % add padding
            M(:,:,end+1,:)=max(abs(M(:)));
            M(:,:,:,end+1)=max(abs(M(:)));            
            % reorder for plotting
            N = reshape(permute(M,[3,1,4,2,5]),fs(1)*(fs(3)+1),fs(2)*(fs(4)+1),[]);
            % plot
            chns = featuremodel.siftPipelineConfig.channels;
            if args.signed
                imagesc(N,'XData',[0.5 length(chns)+0.5],'YData',[0.5 length(chns)+0.5]);
                caxis([-max(abs(N(:))) max(abs(N(:)))])
            else
                imagesc(abs(N),'XData',[0.5 length(chns)+0.5],'YData',[0.5 length(chns)+0.5]);
            end
            colorbar;
            title('Absolute model weights across component pairs in time/frequency.');            
            xlabel('From Component');
            set(gca,'XTick',1:length(chns),'XTickLabel',chns);
            set(gca,'YTick',1:length(chns),'YTickLabel',chns);
            ylabel('To Component');
        end

        function layout = dialog_layout_defaults(self)
            % define the default configuration dialog layout 
            layout = {'SignalProcessing.Resampling.SamplingRate', ...
                'SignalProcessing.DataCleaning.DataSetting', ...
                '', ...
                'SignalProcessing.ICA.Variant', ...
                '', ...
                'SignalProcessing.ChannelSelection.Channels', ...
                '', ...
                'SignalProcessing.EpochExtraction', ...
                '', ...
                'Prediction.FeatureExtraction.ValueFormat', ...
                '', ...
                'Prediction.FeatureExtraction.ConnectivityPipeline.Modeling.ModelOrder', ...
                'Prediction.FeatureExtraction.ConnectivityPipeline.Modeling.WindowLength', ...
                'Prediction.FeatureExtraction.ConnectivityPipeline.Modeling.WindowStepSize', ...
                'Prediction.FeatureExtraction.ConnectivityPipeline.Connectivity.Frequencies', ...
                'Prediction.FeatureExtraction.ConnectivityPipeline.Connectivity.ConnectivityMeasures', ...
                '', ...
                'Prediction.MachineLearning.Learner.LossType', ...
                'Prediction.MachineLearning.Learner.LambdaSearch.Lambdas', ...
                'Prediction.MachineLearning.Learner.LambdaSearch.ParameterMetric', ...
                'Prediction.MachineLearning.Learner.LambdaSearch.NumFolds'};
        end
                
        function tf = needs_voting(self)
            % by default we use voting to handle more than two classes
            tf = true; 
        end
        
        function sig = make_continuous(self,sig)
            % turn an epoched signal into a continuous one
            if sig.trials ~= 1
                % epoched dataset... reshape it
                sig.data = sig.data(:,:);
                if isfield(sig,'srcpot') && ~isempty(sig.srcpot)
                    sig.srcpot = sig.srcpot(:,:); end
                if isfield(sig,'icaact') && ~isempty(sig.icaact)
                    sig.icaact = sig.icaact(:,:); end
                [sig.chns,sig.pnts,sig.trials] = size(sig.data);
                sig.epoch = [];
                sig.event = [];
            end
        end
        
    end
end

