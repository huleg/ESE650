clear all
close all
%clc

pattern = {'beat3','beat4','circle','eight','inf','wave'};
contents = dir('data');
file_names = cell(length(contents),1);
for file_idx = 1:length(contents)
    file_names{file_idx} = contents(file_idx).name;...
end

for pattern_num = 1:length(pattern)
    acc = [];
    orient = [];
    time = [];
    valid_files = find(~cellfun(@isempty,regexp(file_names,['^' pattern{pattern_num} '.+(\.mat)$'])));
    for i = 1:length(valid_files)
        data = load(['data/' file_names{valid_files(i)}]);
        acc = [acc data.full_data.acceleration];
        orient = [orient data.full_data.orientation];
        time = [time data.full_data.time'];
    end
    
    %{
    acc_g = zeros(size(acc));
    for i = 1:length(time)
        acc_i = quat_mult(quat_mult(orient(:,i),[0; acc(:,i)]),quat_conj(orient(:,i)));
        acc_g(:,i) = acc_i(2:4);
    end
    %}
    
    M = 30;
    [O,C] = kmeans(orient',M);
    N = 10;
    max_iter = 500;
    params = baum_welch(O,M,N,max_iter);
    params.C = C;
    params.A
    params.B
    fprintf('-----------------------------\n')
    save(['models/' pattern{pattern_num} '_params.mat'],'params')
end