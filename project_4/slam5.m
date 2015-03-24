%clear all
close all

%% add important directories
addpath('mex')
addpath('cameraParam')
IRcamera_Calib_Results
RGBcamera_Calib_Results

%% load data
joints = load('joint3.mat');
lidar_dat = load('lidar3.mat');
rgb = load('rgb3.mat');
depth = load('depth3.mat');
iNeck = get_joint_index('Neck'); % head yaw
iHead = get_joint_index('Head'); % head pitch
joints.pos = joints.pos';

lidar.lidar = cell(1,length(1:10:size(lidar_dat.lidar,2)));
lidar.lidar = lidar_dat.lidar(1:10:end);


%% occupancy grid initialization
x_len = 30;
y_len = 30;
z_len = 5;
resolution = 0.02;
offset_x = x_len/2;
offset_y = y_len/2;
offset_z = 0;
dec_place = floor(log10(resolution));
val = floor(abs(resolution) ./ 10.^dec_place);
map_2 = zeros(floor(x_len/resolution),floor(y_len/resolution));
map_dims = size(map_2);
path = zeros(length(lidar.lidar),3);

%% plot
figure(4)
clf
lidar_2d = imshow(1./(1+exp(-map_2))); % log odds map plot
hold on
grid on
set(gca,'ydir','normal')
axis equal
robot_y = [1 0 -1]*0.5;
robot_x = [-1 2 -1]*0.5;
robot_plot = fill(robot_x,robot_y,'g'); % robot pose plot
robot_pos = plot(offset_x,offset_y,'r-'); % robot path plot


%% time stamps of lidar data
lidar_t = zeros(1,length(lidar.lidar));
lidar_idx = 1;
for i = 1:length(lidar.lidar)
    lidar_t(i) = lidar.lidar{i}.t;%-joints.t0;
end
lidar_angles = linspace(-135,135,1081)'*pi/180;

%% main loop
nbytes = 0;
num_angles = 20;
patch_width = 7;
num_particles = num_angles*patch_width^2;
log_odd_threshold = 1000;
H_bod = repmat(eye(4),1,1,num_particles);
lidar_points = zeros(1081,num_particles*4);
weights = ones(1,num_particles)/num_particles;
scaled_offset_mat = repmat(round([offset_x offset_y offset_z 0]/resolution),1,num_particles);
gt_mask_mat = repmat([x_len y_len 1.5 1]/resolution,1,num_particles);
lt_mask_mat = repmat([1 1 0.1/resolution 1],1,num_particles);

best_particle = zeros(3,1);
[o_x,o_y] = meshgrid(0:resolution:(patch_width-1)*resolution);
particle_offset = [reshape(o_x,1,patch_width^2)-floor(patch_width/2)*resolution;...
                    reshape(o_y,1,patch_width^2)-floor(patch_width/2)*resolution];
particles = zeros(3,num_particles);
[~,i_0] = min(abs(lidar_t(1) - joints.ts));
dX_mat = [];
for i = i_0:length(joints.ts)
    %% process new lidar hits
    [~,idx] = min(abs(lidar_t - joints.ts(i)));
    if idx ~= lidar_idx
        lidar_idx = idx;

        %% get odometry data in local frame
        body_roll = lidar.lidar{lidar_idx}.rpy(1);
        body_pitch = lidar.lidar{lidar_idx}.rpy(2);
        body_yaw = lidar.lidar{lidar_idx}.rpy(3) - lidar.lidar{1}.rpy(3);
        bod_pose = lidar.lidar{lidar_idx}.pose;
        bod_pose(3) = body_yaw;
                
        if lidar_idx == 1
            dX = [0 0]';
            dtheta = 0;
        else
            body_yaw_prev = lidar.lidar{lidar_idx-1}.rpy(3) - lidar.lidar{1}.rpy(3);
            bod_pose_prev = lidar.lidar{lidar_idx-1}.pose;
            bod_pose_prev(3) = body_yaw_prev;
            dtheta = body_yaw-body_yaw_prev;
            dX = [cos(body_yaw_prev) sin(body_yaw_prev); -sin(body_yaw_prev) cos(body_yaw_prev)]'*(bod_pose(1:2)-bod_pose_prev(1:2))';
            dX_mat = [dX_mat dX];
        end
        
        %% motion model update on particles
        thetas = dtheta + normrnd(0,abs(dtheta),[1 num_angles]);
        %thetas = dtheta + dtheta*linspace(-1,1,num_angles);
        for j = 1:num_angles
            particles(1:2,(j-1)*patch_width^2+1:j*patch_width^2) = bsxfun(@plus,best_particle(1:2),particle_offset);
            particles(3,(j-1)*patch_width^2+1:j*patch_width^2) = best_particle(3) + thetas(j);
        end
        
        for j = 1:num_particles
            particles(1:2,j) = particles(1:2,j) + [cos(particles(3,j)) -sin(particles(3,j)); sin(particles(3,j)) cos(particles(3,j))]*dX;
        end
        
        %% get homogeneous transforms of each particle
        for j = 1:num_particles
            H_bod(:,:,j) = get_hom_transform(euler_to_rot(body_roll,body_pitch,particles(3,j)),[particles(1:2,j); 0]);
        end
        
        %% get homogeneous transform of head
        H_cam = get_hom_transform(eye(3),[0 0 0.395])*get_hom_transform(euler_to_rot(0,joints.pos(i,iHead),joints.pos(i,iNeck)),[0 0 0.085]);
        
        %% get rotated lidar scan in 3d (no translation)
        lidar_scan = lidar.lidar{lidar_idx}.scan';
        lidar_cart = [lidar_scan.*cos(lidar_angles) lidar_scan.*sin(lidar_angles) zeros(length(lidar_scan),1) ones(length(lidar_scan),1)];
        
        %transforms = bsxfun(@times,H_bod,H_cam);
        for j = 1:num_particles
            lidar_points(:,4*j-3:4*j) = (H_bod(:,:,j)*H_cam*lidar_cart')';
            %lidar_points(:,4*j-3:4*j) = (transforms(:,:,j)*lidar_cart')';
        end
        
        % get rid of bad lidar hits
        lidar_mask = lidar_scan>0.025;
        lidar_window = 1:1081> 0 & 1:1081 < 1081;
        lidar_points_masked = lidar_points(lidar_mask & lidar_window',:);
        
        %% get correlations
        lidar_scaled = bsxfun(@plus,round(lidar_points_masked/resolution), scaled_offset_mat);
        mask = any(bsxfun(@gt, lidar_scaled, gt_mask_mat),2) | any(bsxfun(@lt,lidar_scaled, lt_mask_mat),2);
        lidar_scaled(mask,:) = [];
        for j = 1:num_particles
            lidar_test = lidar_scaled(:,4*j-3:4*j-1);
            lidar_linidx = lidar_test(:,1)+(lidar_test(:,2)-1)*map_dims(2);
            weights(j) = sum(map_2(lidar_linidx));
        end
        
        %% update map based on most likely particle
        % get lidar hits of best particle
        [~,best_particle_idx] = max(weights);
        best_particle = particles(:,best_particle_idx);
        lidar_hits = lidar_scaled(:,best_particle_idx*4-3:best_particle_idx*4-2);
        lidar_z = lidar_scaled(:,best_particle_idx*4-1);
        
        % update positive hits
        mask = any(bsxfun(@gt, lidar_hits(:,1:2), [x_len y_len]/resolution),2) | any(bsxfun(@lt,lidar_hits(:,1:2),[1 1]),2);
        lidar_hits(mask>0,:) = [];
        lidar_linidx = lidar_hits(:,1)+(lidar_hits(:,2)-1)*map_dims(2);
        map_2(uint64(lidar_linidx)) = map_2(uint64(lidar_linidx)) + 1;
        
        % update negative hits
        x_start = round((best_particle(1)+offset_x)/resolution);
        y_start = round((best_particle(2)+offset_y)/resolution);
        [x_b,y_b] = getMapCellsFromRay(repmat(x_start,1,size(lidar_hits,1))',...
                                       repmat(y_start,1,size(lidar_hits,1))',...
                                        double(lidar_hits(:,1))',...
                                        double(lidar_hits(:,2))');
                                    
        mask = x_b > 0 & y_b > 0;% & x_b < size(map_2,1) & y_b < size(map_2,2);
        lidar_nlinidx = uint64(x_b+(y_b-1)*map_dims(2));
        map_2(lidar_nlinidx) = map_2(lidar_nlinidx) - 0.7;
        map_2 = min(map_2,log_odd_threshold);
        map_2 = max(map_2,-log_odd_threshold);
        
        %% store path
        pos = [best_particle(1:2)' 0]';
        if sum(pos' == path(end,:)) < 3
            path(lidar_idx,:) = pos';
        end
    end
    
    %% redraw plots
    n = 20;
    if ~mod(i,n)
        % print the time
        fprintf(repmat('\b',1,nbytes));
        nbytes = fprintf('time: %6.6f',joints.ts(i) - joints.ts(1));
        %{d
        % plot 2d
        set(lidar_2d,'cdata',imrotate(1./(1+exp(-fliplr(map_2))),90));
        set(robot_pos,'xdata',(path(1:lidar_idx,1)+offset_x)/resolution,'ydata',(path(1:lidar_idx,2)+offset_y)/resolution)
        %new_robot_pos = [cos(lidar.lidar{lidar_idx}.rpy(3) - lidar.lidar{1}.rpy(3)) -sin(lidar.lidar{lidar_idx}.rpy(3) - lidar.lidar{1}.rpy(3)); sin(lidar.lidar{lidar_idx}.rpy(3) - lidar.lidar{1}.rpy(3)) cos(lidar.lidar{lidar_idx}.rpy(3) - lidar.lidar{1}.rpy(3))]*[robot_x;robot_y];
        new_robot_pos = [cos(body_yaw) -sin(body_yaw); sin(body_yaw) cos(body_yaw)]*[robot_x;robot_y];
        set(robot_plot,'xdata',(new_robot_pos(1,:)+path(lidar_idx,1)+offset_x)/resolution,'ydata',(new_robot_pos(2,:)+path(lidar_idx,2)+offset_y)/resolution)
        drawnow
        %}
    end
end
fprintf('\n')