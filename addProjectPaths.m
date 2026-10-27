function addProjectPaths()
%ADDPROJECTPATHS Add the demo root folder to the MATLAB path.
%
%   ADDPROJECTPATHS makes the +evcharge package visible from MATLAB,
%   Simulink, and the test suite.

demoRoot = fileparts(mfilename("fullpath"));
addpath(demoRoot);
end
