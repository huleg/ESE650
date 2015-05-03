 
R1 = [cos(pi/4) -sin(pi/4) 0; sin(pi/4) cos(pi/4) 0; 0 0 1];
t1 = [0 2 0]';
H1 = [R1 t1; 0 0 0 1];
H2 = [eye(3) [0 0.5 0]'; 0 0 0 1];
H3 = H1*H2

R2 = H3(1:3,1:3);
t2 = H3(1:3,4);

figure(1)
clf
quiver3(t2(1),t2(2),t2(3),R2(1,1),R2(2,1),R2(3,1))
hold on
quiver3(t2(1),t2(2),t2(3),R2(1,2),R2(2,2),R2(3,2))
quiver3(t2(1),t2(2),t2(3),R2(1,3),R2(2,3),R2(3,3))

quiver3(t1(1),t1(2),t1(3),R1(1,1),R1(2,1),R1(3,1))
quiver3(t1(1),t1(2),t1(3),R1(1,2),R1(2,2),R1(3,2))
quiver3(t1(1),t1(2),t1(3),R1(1,3),R1(2,3),R1(3,3))
axis equal
