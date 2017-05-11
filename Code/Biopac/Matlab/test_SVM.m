%% Testing SVM Model from Training 

%% load SVM model
addpath('data');
load('AS02_obj022.mat'); % Alex' data set AS02 with objective function value of 0.22

%% extract pre-processed data
testX = redFeatures(:,:);

%% test data for data label
label = predict(SVMModel, testX');

%% test 'corrupt' data 
corruptX = randn(size(redFeatures));
corruptX = corruptX .* redFeatures;

labelCorrupt = predict(SVMModel, corruptX');

